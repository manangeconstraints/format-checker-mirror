require File.join(File.expand_path(File.dirname(__FILE__)), '../constraint_analyzer/parse_sql.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), '../constraint_analyzer/validate.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), '../constraint_analyzer/parse_model_constraint.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), '../constraint_analyzer/parse_db_constraint.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), '../constraint_analyzer/read_files.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), '../constraint_analyzer/class_class.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), '../constraint_analyzer/helper.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), '../constraint_analyzer/version.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), '../constraint_analyzer/extract_statistics.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), '../constraint_analyzer/ast_handler.rb')
require "test/unit"
require 'yard'
require 'active_support'
require 'active_support/inflector'
require 'active_support/core_ext/string'
class TestParseModelConstriant < Test::Unit::TestCase
  def test_parse_confirmation
  	contents = "class ChangeProductsPrice < ActiveRecord::Migration[5.0]
                def change
                  reversible do |dir|
                    change_table :products do |t|
                      dir.up   { t.change :price, :string }
                      dir.down { t.change :price, :integer }
                    end
                  end
                end
              end" 
  	ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    model_class = Class_class.new("products.rb")
    model_class.class_name = "Product"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = Class_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)  
    assert_equal 1, model_class.getColumns.length
    assert_equal 0, model_class.getConstraints.length
  end
  def test_remove_column
    contents = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                    remove_column :products, :part_number, :string
                  end
                end" 
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    model_class = Class_class.new("products.rb")
    model_class.class_name = "Product"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = Class_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)  
    assert_equal 1, model_class.getColumns.length
    assert_equal 0, model_class.getConstraints.length
    column = model_class.getColumns.values[0]
    assert_equal true, column&.is_deleted
    assert_equal 'part_number', column.column_name
    assert_equal 'string', column.column_type
    assert_equal 'part_number', model_class.getColumns.keys[0]
  end
  def test_add_column
    contents = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                    add_column :products, :part_number, :string, default: ''
                  end
                end" 
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    puts "ast: #{ast.source}"
    model_class = Class_class.new("products.rb")
    model_class.class_name = "Product"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = Class_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)  
    assert_equal 1, model_class.getColumns.length
    assert_equal 0, model_class.getConstraints.length
    column = model_class.getColumns.values[0]
    assert_equal false, column&.is_deleted
    assert_equal 'part_number', column.column_name
    assert_equal 'string', column.column_type
    assert_equal 'part_number', model_class.getColumns.keys[0]
    assert_equal '', column.default_value
  end
  def test_change_column_default
    contents1 = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                      change_column_default :products, :approved, from: true, to: false
                  end
                end" 
    ast1 = YARD::Parser::Ruby::RubyParser.parse(contents1).root
    contents = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                      add_column :products, :approved, :boolean, default: true
                  end
                end" 
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    
    model_class = Class_class.new("products.rb")
    model_class.class_name = "Product"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = Class_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)  
    assert_equal 1, model_class.getColumns.length
    assert_equal 0, model_class.getConstraints.length
    column = model_class.getColumns.values[0]
    assert_equal false, column&.is_deleted
    assert_equal 'approved', column.column_name
    assert_equal 'boolean', column.column_type
    assert_equal "true", column.default_value

    $cur_class = Class_class.new("test2.rb")
    $cur_class.ast = ast1
    parse_db_constraint_file(ast1)  
    assert_equal 1, model_class.getColumns.length
    assert_equal 0, model_class.getConstraints.length
    column = model_class.getColumns.values[0]
    assert_equal false, column&.is_deleted
    assert_equal 'approved', column.column_name
    assert_equal 'boolean', column.column_type
    assert_equal "false", column.default_value
  end
end
