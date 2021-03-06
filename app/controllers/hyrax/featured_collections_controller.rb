module Hyrax
  class FeaturedCollectionsController < ApplicationController

    def create
      authorize! :create, FeaturedCollection
      @featured_collection = FeaturedCollection.new(collection_id: params[:collection_id])

      respond_to do |format|
        if @featured_collection.save
          format.json {
            head :no_content
            # redirect_to collection_path(:collection_id)
            # render json: @featured_collection, status: :created
          }
        else
          format.json { render json: @featured_collection.errors, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      authorize! :destroy, FeaturedCollection
      @featured_collection = FeaturedCollection.find_by(collection_id: params[:collection_id])
      @featured_collection&.destroy

      respond_to do |format|
        format.json { head :no_content }
      end
    end

  end
end
