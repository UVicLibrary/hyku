module Hyrax
  module Renderers
    class DateCreatedRenderer < AttributeRenderer

      # Converted into a year range rather than a text search.

    private

      def li_value(value)
        link_to(value, search_path)
      end

      def search_path
        if options.fetch(:begin).present? and options.fetch(:end).present?
          Rails.application.routes.url_helpers.search_catalog_path + range_params_string(options.fetch(:begin), options.fetch(:end))
        else
          Rails.application.routes.url_helpers.search_catalog_path + "?range[year_range_isim][missing]=true"
        end
      end

      def range_params_string(first, last)
        "?range[year_range_isim][begin]=#{first}&range[year_range_isim][end]=#{last}"
      end

    end
  end
end