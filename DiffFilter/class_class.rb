class Class_class
	attr_accessor :filename, :class_name, :upper_class_name, :ast, :is_activerecord
	def initialize(filename)
		@filename = filename
		@is_activerecord = false
		@name = nil
		@upper_class_name = nil
		@ast = nil
		@constraints = []
	end
end