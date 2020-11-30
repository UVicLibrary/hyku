# Generated by hyrax:models:install
class FileSet < ActiveFedora::Base

	property :creator, predicate: ::RDF::Vocab::DC11.creator, class_name: Hyrax::ControlledVocabularies::Creator


  property :alternative_title, predicate: ::RDF::Vocab::DC.alternative do |index|
	index.as :stored_searchable, :facetable
  end

  property :edition, predicate: ::RDF::Vocab::SCHEMA.bookEdition do |index|
	index.as :stored_searchable, :facetable
  end

  property :geographic_coverage, predicate: ::RDF::Vocab::DC.spatial, class_name: Hyrax::ControlledVocabularies::GeographicCoverage

  property :coordinates, predicate: ::RDF::Vocab::SCHEMA.geo do |index|
	index.as :stored_searchable, :facetable
  end

  property :chronological_coverage, predicate: ::RDF::Vocab::DC.temporal do |index|
	index.as :stored_searchable, :facetable
  end

  property :extent, predicate: ::RDF::Vocab::DC.extent do |index|
	index.as :stored_searchable, :facetable
  end

  property :additional_physical_characteristics, predicate: ::RDF::Vocab::SCHEMA.description do |index|
	index.as :stored_searchable, :facetable
  end

  property :has_format, predicate: ::RDF::Vocab::DC.hasFormat do |index|
	index.as :stored_searchable, :facetable
  end

  property :physical_repository, predicate: ::RDF::Vocab::PROV.atLocation do |index|
	index.as :stored_searchable, :facetable
  end

  property :provenance, predicate: ::RDF::Vocab::DC.provenance do |index|
	index.as :stored_searchable, :facetable
  end

  property :provider, predicate: ::RDF::Vocab::EDM.provider, class_name: Hyrax::ControlledVocabularies::Provider
  
  property :sponsor, predicate: ::RDF::Vocab::SCHEMA.sponsor do |index|
	index.as :stored_searchable, :facetable
  end
  
  property :genre, predicate: ::RDF::Vocab::SCHEMA.genre, class_name: Hyrax::ControlledVocabularies::Genre

  property :format, predicate: ::RDF::Vocab::DC.format do |index|
	index.as :stored_searchable, :facetable
  end

  property :is_referenced_by, predicate: ::RDF::Vocab::DC.isReferencedBy do |index|
	index.as :stored_searchable, :facetable
  end

  property :date_digitized, predicate: ::RDF::Vocab::DC.date, multiple: false do |index|
	index.as :stored_searchable, :facetable
  end

  property :transcript, predicate: ::RDF::Vocab::SCHEMA.transcript do |index|
	index.as :stored_searchable, :facetable
  end

  property :technical_note, predicate: ::RDF::URI.new('http://uvic.ca/ns/uvic#technicalNote') do |index|
	index.as :stored_searchable, :facetable
  end

  property :year, predicate: ::RDF::URI.new('http://library.uvic.ca/ns/uvic#year')


  include ::Hyrax::FileSetBehavior
  
  property :creator, predicate: ::RDF::Vocab::DC11.creator, class_name: Hyrax::ControlledVocabularies::Creator
      
  property :contributor, predicate: ::RDF::Vocab::DC11.contributor, class_name: Hyrax::ControlledVocabularies::Contributor
  
  property :subject, predicate: ::RDF::Vocab::DC11.subject, class_name: Hyrax::ControlledVocabularies::Subject
  

  before_destroy :remove_rendering_relationship

  # Hyku has its own FileSetIndexer: app/indexers/file_set_indexer.rb
  # It overrides Hyrax to inject IIIF behavior.
  self.indexer = FileSetIndexer

  def rendering_ids
    to_param
  end

  id_blank = proc { |attributes| attributes[:id].blank? }
  
  self.controlled_properties += [:creator, :contributor, :physical_repository, :provider, :subject, :geographic_coverage, :genre]
  accepts_nested_attributes_for :creator, reject_if: id_blank, allow_destroy: true
  accepts_nested_attributes_for :contributor, reject_if: id_blank, allow_destroy: true
  accepts_nested_attributes_for :physical_repository, reject_if: id_blank, allow_destroy: true
  accepts_nested_attributes_for :provider, reject_if: id_blank, allow_destroy: true
  accepts_nested_attributes_for :subject, reject_if: id_blank, allow_destroy: true
  accepts_nested_attributes_for :geographic_coverage, reject_if: id_blank, allow_destroy: true
  accepts_nested_attributes_for :genre, reject_if: id_blank, allow_destroy: true


  def required?(term)
    Hyrax::FileSetForm.required_fields.include?(term)
  end

	def pdf_thumbnail_path
		gw = GenericWork.where(member_ids_ssim: self.id).first
		if gw.present? && gw.member_of_collections.first.present?
			default_path = "/pdf_thumbnails/#{gw.member_of_collections.first.title.first.parameterize.underscore}/#{self.id}-thumb.jpg"
			if File.exist?("/usr/local/rails/vault/public#{default_path}")
				default_path
			else
				"/pdf_thumbnails/misc/#{self.id}-thumb.jpg"
			end
		else # If work does not belong to a collection
			"/pdf_thumbnails/misc/#{self.id}-thumb.jpg"
		end
	end

  private

    # If any parent objects are pointing at this object as their
    # rendering, remove that pointer.
    def remove_rendering_relationship
      parent_objects = parents
      return if parent_objects.empty?
      parent_objects.each do |work|
        if work.rendering_ids.include(id)
          new_rendering_ids = work.rendering_ids.delete(id)
          work.update(rendering_ids: new_rendering_ids)
        end
      end
    end
end
