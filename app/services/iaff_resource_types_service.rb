class IaffResourceTypesService < Hyrax::QaSelectService
	def initialize(_authority_name = nil)
	  super('iaff_resource_types')
	end
	mattr_accessor :authority
	self.authority = Qa::Authorities::Local.subauthority_for('iaff_resource_types')

	def self.select_options
		authority.all.map do |element|
			[element[:label], element[:id]]
		end
	end

	def self.label(id)
		authority.find(id).fetch('term') rescue id
	end

	##
	# @param [String, nil] id identifier of the resource type
	#
	# @return [String] a schema.org type. Gives the default type if `id` is nil.
	def self.microdata_type(id)
		return Hyrax.config.microdata_default_type if id.nil?
		Microdata.fetch("resource_type.#{id}", default: Hyrax.config.microdata_default_type)
	end
end


