require 'iiif_manifest'
require 'iiif/presentation'

module Hyrax
  module WorksControllerBehavior
    extend ActiveSupport::Concern
    include Blacklight::Base
    include Blacklight::AccessControls::Catalog

    included do
      with_themed_layout :decide_layout
      copy_blacklight_config_from(::CatalogController)

      class_attribute :_curation_concern_type, :show_presenter, :work_form_service, :search_builder_class
      class_attribute :iiif_manifest_builder, instance_accessor: false
      self.show_presenter = ::HykuWorkShowPresenter # Hyrax::WorkShowPresenter
      self.work_form_service = Hyrax::WorkFormService
      self.search_builder_class = WorkSearchBuilder
      attr_accessor :curation_concern
      helper_method :curation_concern, :contextual_path

      rescue_from WorkflowAuthorizationException, with: :render_unavailable
    end

    class_methods do
      def curation_concern_type=(curation_concern_type)
        load_and_authorize_resource class: curation_concern_type, instance_name: :curation_concern, except: [:show, :file_manager, :inspect_work, :manifest]

        # Load the fedora resource to get the etag.
        # No need to authorize for the file manager, because it does authorization via the presenter.
        load_resource class: curation_concern_type, instance_name: :curation_concern, only: :file_manager

        self._curation_concern_type = curation_concern_type
        # We don't want the breadcrumb action to occur until after the concern has
        # been loaded and authorized
        before_action :save_permissions, only: :update
      end

      def curation_concern_type
        _curation_concern_type
      end

      def cancan_resource_class
        Hyrax::ControllerResource
      end
    end

    def new
      # TODO: move these lines to the work form builder in Hyrax
      curation_concern.depositor = current_user.user_key
      curation_concern.admin_set_id = admin_set_id_for_new
      build_form
    end

    def create
      downloadable_to_boolean
      if actor.create(actor_environment)
        after_create_response
      else
        respond_to do |wants|
          wants.html do
            build_form
            render 'new', status: :unprocessable_entity
          end
          wants.json { render_json_response(response_type: :unprocessable_entity, options: { errors: curation_concern.errors }) }
        end
      end
    end

    # Finds a solr document matching the id and sets @presenter
    # @raise CanCan::AccessDenied if the document is not found or the user doesn't have access to it.
    def show
      @user_collections = user_collections

      respond_to do |wants|
        wants.html { presenter && parent_presenter }
        wants.json do
          # load @curation_concern manually because it's skipped for html
          @curation_concern = Hyrax.query_service.find_by_alternate_identifier(alternate_identifier: params[:id])
          render :show, status: :ok
        end
        additional_response_formats(wants)
        wants.ttl do
          render body: presenter.export_as_ttl, mime_type: Mime[:ttl]
        end
        wants.jsonld do
          render body: presenter.export_as_jsonld, mime_type: Mime[:jsonld]
        end
        wants.nt do
          render body: presenter.export_as_nt, mime_type: Mime[:nt]
        end
      end
    end

    def edit
      build_form
    end

    def update
      downloadable_to_boolean
      if actor.update(actor_environment)
        after_update_response
      else
        respond_to do |wants|
          wants.html do
            build_form
            render 'edit', status: :unprocessable_entity
          end
          wants.json { render_json_response(response_type: :unprocessable_entity, options: { errors: curation_concern.errors }) }
        end
      end
    end

    def destroy
      title = curation_concern.to_s
      env = Actors::Environment.new(curation_concern, current_ability, {})
      return unless actor.destroy(env)
      Hyrax.config.callback.run(:after_destroy, curation_concern.id, current_user, warn: false)
      after_destroy_response(title)
    end

    def file_manager
      @form = Forms::FileManagerForm.new(curation_concern, current_ability)
    end

    def inspect_work
      raise Hydra::AccessDenied unless current_ability.admin?
      presenter
    end

    def manifest
      headers['Access-Control-Allow-Origin'] = '*'

      if Account.find_by(tenant: Apartment::Tenant.current)&.cname.include?("vault")
        # Use the manifest created by the IIIF Manifest gem as a base
        manifest = IIIF::Service.parse(JSON.parse(manifest_builder.to_h.to_json))
        # Assign work-level metadata (not just required fields)
        manifest.metadata = presenter.manifest_metadata
        manifest.sequences.first.canvases.each do |canvas|
          fs_id = canvas["@id"].split('/').last
          fs = ::FileSet.find(fs_id)
          resource = canvas.images.first.resource
          # Add title and description
          resource.label = fs.title.first
          resource.description = fs.description.first
          # Add other metadata
          metadata_labels = fs.attribute_names -
              ["head", "tail", "date_uploaded", "depositor", "date_modified",
               "relative_path", "import_url", "based_near", "access_control_id",
               "embargo_id", "lease_id", "label", "description", "title"] # Don't need these last 3 because they are handled separately
          metadata = metadata_labels.each_with_object([]) do |label_name, array|
            key = label_name.to_s.humanize
            value = fs[label_name].first
            next unless value.present?
            array.push(key => value)
          end
          resource.metadata = metadata
        end
        json = manifest.to_json(pretty: true)
      else
        json = sanitize_manifest(JSON.parse(manifest_builder.to_h.to_json))
      end


      respond_to do |wants|
        wants.json { render json: json }
        wants.html { render json: json }
      end
    end

    private

      def downloadable_to_boolean
        if params[:generic_work] && params[:generic_work][:downloadable].present?
          params[:generic_work][:downloadable] = ActiveModel::Type::Boolean.new.cast(params[:generic_work][:downloadable])
        end	
      end

      def user_collections
        collections_service.search_results(:deposit)
      end

      def collections_service
        Hyrax::CollectionsService.new(self)
      end

      def admin_set_id_for_new
        # admin_set_id is required on the client, otherwise simple_form renders a blank option.
        # however it isn't a required field for someone to submit via json.
        # Set the default admin set if it exists; otherwise, set to first admin_set they have access to.
        admin_sets = Hyrax::AdminSetService.new(self).search_results(:deposit)
        return nil if admin_sets.blank? # shouldn't happen
        return AdminSet::DEFAULT_ID if admin_sets.map(&:id).include?(AdminSet::DEFAULT_ID)
        admin_sets.first.id
      end

      def build_form
        @form = work_form_service.build(curation_concern, current_ability, self)
      end

      def manifest_builder
        ::IIIFManifest::ManifestFactory.new(presenter)
      end

      def actor
        @actor ||= Hyrax::CurationConcern.actor
      end

      def presenter
        @presenter ||= show_presenter.new(curation_concern_from_search_results, current_ability, request)
      end

      def parent_presenter
        return @parent_presenter unless params[:parent_id]

        @parent_presenter ||=
          show_presenter.new(search_result_document(id: params[:parent_id]), current_ability, request)
      end

      # Include 'hyrax/base' in the search path for views, while prefering
      # our local paths. Thus we are unable to just override `self.local_prefixes`
      def _prefixes
        @_prefixes ||= super + ['hyrax/base']
      end

      def actor_environment
        Actors::Environment.new(curation_concern, current_ability, attributes_for_actor)
      end

      def hash_key_for_curation_concern
        _curation_concern_type.model_name.param_key
      end

      def contextual_path(presenter, parent_presenter)
        ::Hyrax::ContextualPath.new(presenter, parent_presenter).show
      end

      def curation_concern_from_search_results
        search_params = params
        search_params.delete :page
        search_result_document(search_params)
      end

      # Only returns unsuppressed documents the user has read access to
      def search_result_document(search_params)
        _, document_list = search_results(search_params)
        return document_list.first unless document_list.empty?
        document_not_found!
      end

      def document_not_found!
        doc = ::SolrDocument.find(params[:id])
        raise WorkflowAuthorizationException if doc.suppressed? && current_ability.can?(:read, doc)
        raise CanCan::AccessDenied.new(nil, :show)
      end

      def render_unavailable
        message = I18n.t("hyrax.workflow.unauthorized")
        respond_to do |wants|
          wants.html do
            unavailable_presenter
            flash[:notice] = message
            render 'unavailable', status: :unauthorized
          end
          wants.json do
            render plain: message, status: :unauthorized
          end
          additional_response_formats(wants)
          wants.ttl do
            render plain: message, status: :unauthorized
          end
          wants.jsonld do
            render plain: message, status: :unauthorized
          end
          wants.nt do
            render plain: message, status: :unauthorized
          end
        end
      end

      def unavailable_presenter
        @presenter ||= show_presenter.new(::SolrDocument.find(params[:id]), current_ability, request)
      end

      def decide_layout
        layout = case action_name
                 when 'show'
                   '1_column'
                 else
                   'dashboard'
                 end
        File.join(theme, layout)
      end

      # Add uploaded_files to the parameters received by the actor.
      def attributes_for_actor
        raw_params = params[hash_key_for_curation_concern]
        attributes = if raw_params
                       work_form_service.form_class(curation_concern).model_attributes(raw_params)
                     else
                       {}
                     end

        # If they selected a BrowseEverything file, but then clicked the
        # remove button, it will still show up in `selected_files`, but
        # it will no longer be in uploaded_files. By checking the
        # intersection, we get the files they added via BrowseEverything
        # that they have not removed from the upload widget.
        uploaded_files = params.fetch(:uploaded_files, [])
        selected_files = params.fetch(:selected_files, {}).values
        browse_everything_urls = uploaded_files &
                                 selected_files.map { |f| f[:url] }

        # we need the hash of files with url and file_name
        browse_everything_files = selected_files
                                  .select { |v| uploaded_files.include?(v[:url]) }
        attributes[:remote_files] = browse_everything_files
        # Strip out any BrowseEverthing files from the regular uploads.
        attributes[:uploaded_files] = uploaded_files -
                                      browse_everything_urls
        attributes
      end

      def after_create_response
        respond_to do |wants|
          wants.html do
            # Calling `#t` in a controller context does not mark _html keys as html_safe
            flash[:notice] = view_context.t('hyrax.works.create.after_create_html', application_name: view_context.application_name)
            redirect_to [main_app, curation_concern]
          end
          wants.json { render :show, status: :created, location: polymorphic_path([main_app, curation_concern]) }
        end
      end

      def after_update_response
        if curation_concern.file_sets.present?
          return redirect_to hyrax.confirm_access_permission_path(curation_concern) if permissions_changed?
          return redirect_to main_app.confirm_hyrax_permission_path(curation_concern) if curation_concern.visibility_changed?
        end
        respond_to do |wants|
          wants.html { redirect_to [main_app, curation_concern], notice: "Work \"#{curation_concern}\" successfully updated." }
          wants.json { render :show, status: :ok, location: polymorphic_path([main_app, curation_concern]) }
        end
      end

      def after_destroy_response(title)
        respond_to do |wants|
          wants.html { redirect_to my_works_path, notice: "Deleted #{title}" }
          wants.json { render_json_response(response_type: :deleted, message: "Deleted #{curation_concern.id}") }
        end
      end

      def additional_response_formats(format)
        format.endnote do
          send_data(presenter.solr_document.export_as_endnote,
                    type: "application/x-endnote-refer",
                    filename: presenter.solr_document.endnote_filename)
        end
      end

      def save_permissions
        @saved_permissions = curation_concern.permissions.map(&:to_hash)
      end

      def permissions_changed?
        @saved_permissions != curation_concern.permissions.map(&:to_hash)
      end

      def sanitize_manifest(hash)
        hash['label'] = sanitize_value(hash['label']) if hash.key?('label')
        hash['description'] = hash['description']&.collect { |elem| sanitize_value(elem) } if hash.key?('description')

        hash['sequences']&.each do |sequence|
          sequence['canvases']&.each do |canvas|
            canvas['label'] = sanitize_value(canvas['label'])
          end
        end
        hash
      end

      def sanitize_value(text)
        Loofah.fragment(text.to_s).scrub!(:prune).to_s
      end
  end
end
