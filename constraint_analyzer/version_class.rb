class Version_class
  attr_accessor :app_dir, :commit, :total_constraints_num, :db_constraints_num, :model_constraints_num, :html_constraints_num, :loc

  def initialize(app_dir, commit)
    @app_dir = app_dir
    @commit = commit.strip
    @files = {}
    @activerecord_files = {}
    @total_constraints_num = 0
    @db_constraints_num = 0
    @model_constraints_num = 0
    @html_constraints_num = 0
    @db_constraints = []
    @model_constraints = []
    @html_constraints = []
    @loc = 0
  end

  def getDbConstraints
    return @db_constraints
  end

  def getModelConstraints
    return @model_constraints
  end

  def getHtmlConstraints
    return @html_constraints
  end

  def extract_files
    if @app_dir and @commit
      @files = read_constraint_files(@app_dir, @commit)
    end
  end

  def extract_constraints
    num = 0
    @activerecord_files.each do |key, file|
      # puts"#{key} #{file.getConstraints.length}"
      file.create_con_from_column_type
      file.create_con_from_index
      file.create_con_from_format
    end
    @activerecord_files.each do |key, file|
      #file.extract_instance_var_refs
      num += file.getConstraints.length
      file.getConstraints.each do |k, constraint|
        if constraint.type == Constraint::DB
          @db_constraints_num += 1
          @db_constraints << constraint
        elsif constraint.type == Constraint::MODEL
          @model_constraints_num += 1
          @model_constraints << constraint
        elsif constraint.type == Constraint::HTML
          @html_constraints_num += 1
          @html_constraints << constraint
        else
          puts "k: #{k}"
        end
      end
    end
    @total_constraints_num = @db_constraints_num + @model_constraints_num + @html_constraints_num
    total_constraints = @activerecord_files.map { |k, v| v.getConstraints.length }.reduce(:+)
    puts "total_constraints #{total_constraints} #{@total_constraints_num} #{num}"
  end

  def extract_case_insensitive_columns
    ci_columns = {}
    @activerecord_files.each do |key, file|
      constraints = file.getConstraints
      validation_constraints = constraints.select { |k, v| k.include? Constraint::MODEL }
      uniqueness_constraints = validation_constraints.select { |k, v| v.instance_of? Uniqueness_constraint and v.case_sensitive == false }
      # puts "uniqueness_constraints #{uniqueness_constraints.size}"

      columns = file.getColumns
      # puts "Columns #{file.class_name} #{columns.map{|k,v| v.column_name}.join(" ,")}" if columns.size > 0
      uniqueness_constraints.each do |k, v|
        column_name = v.column
        if columns[column_name]
          key = "#{file.class_name}-#{column_name}"
          ci_columns[key] = columns[column_name]
        end
      end
    end
    return ci_columns
  end

  def annotate_model_class
    not_active_files = []
    @files.values.each do |file|
      if ["ActiveRecord::Base", "Spree::Base"].include? file.upper_class_name
        file.is_activerecord = true
      else
        not_active_files << file
      end
    end
    while (true)
      length = not_active_files.length
      not_active_files.each do |file|
        key = file.upper_class_name
        if @files[key] and @files[key].is_activerecord
          file.is_activerecord = true
          not_active_files.delete(file)
        end
      end
      if not_active_files.length == length
        break
      end
    end

    # extract the constraints from the active record file
    @activerecord_files = @files.select { |key, x| x.is_activerecord }
  end

  def get_activerecord_files
    return @activerecord_files
  end

  def print_columns
    # puts"---------------columns-----------------"
    get_activerecord_files.each do |key, file|
      # puts"#{key} #{file.getColumns.length}"
      file.getColumns.each do |key, column|
        # puts"\t#{column.column_name}"
      end
    end
  end

  def compare_constraints(old_version)
    newly_added_constraints = []
    changed_constraints = []
    existing_column_constraints = []
    new_column_constraints = []
    not_match_html_constraints = []
    @activerecord_files.each do |key, file|
      old_file = old_version.get_activerecord_files[key]
      # if the old file doesn't exist, which means it's newly created
      next unless old_file
      constraints = file.getConstraints
      old_constraints = old_file.getConstraints
      old_columns = old_file.getColumns
      constraints.each do |column_keyword, constraint|
        if old_constraints[column_keyword]
          if !constraint.is_same(old_constraints[column_keyword])
            changed_constraints << constraint
            if constraint.type == Constraint::HTML and (not is_html_constraint_match_validate(old_constraints, column_keyword, constraint))
              not_match_html_constraints << constraint
            end
          end
        else
          newly_added_constraints << constraint
          column_name = constraint.column
          if old_columns[column_name]
            existing_column_constraints << constraint
          else
            new_column_constraints << constraint
          end
          if constraint.type == Constraint::HTML and (not is_html_constraint_match_validate(old_constraints, column_keyword, constraint))
            not_match_html_constraints << constraint
          end
        end
      end
    end
    return newly_added_constraints, changed_constraints, existing_column_constraints, new_column_constraints, not_match_html_constraints
  end

  def is_html_constraint_match_validate(old_constraints, column_keyword, constraint)
    key = column_keyword.gsub(Constraint::HTML, Constraint::MODEL)
    key2 = column_keyword.gsub(Constraint::HTML, Constraint::DB)
    old_model_constraint = old_constraints[key]
    old_db_constraint = old_constraints[key2]
    if constraint.is_same_notype(old_model_constraint) or constraint.is_same_notype(old_db_constraint)
      return true
    end
    return false
  end

  def compare_absent_constraints
    db_present_model_absent = []
    model_present_db_absent = []
    @activerecord_files.each do |key, file|
      db_cons = file.getConstraints.select { |k, v| k.include? "-#{Constraint::DB}" }
      model_cons = file.getConstraints.select { |k, v| k.include? "-#{Constraint::MODEL}" }
      html_cons = file.getConstraints.select { |k, v| k.include? "-#{Constraint::HTML}" }

      db_cons.each do |k, v|
        k2 = k.gsub("-#{Constraint::DB}", "-#{Constraint::MODEL}")
        column = file.getColumns[v.column]

        next if !column or column.is_deleted or model_cons[k2]

        if (v.instance_of? Uniqueness_constraint or v.instance_of? Presence_constraint) and column.auto_increment
          db_present_model_absent << { :name => k, :category => :self_satisfied }
        elsif v.instance_of? Presence_constraint and column.default_value
          db_present_model_absent << { :name => k, :category => :self_satisfied }
        elsif model_cons[k.gsub("-#{v.class.name}-", "-#{Customized_constraint.to_s}-")]
          db_present_model_absent << { :name => k, :category => :other }
        elsif v.column == "updated_at" or v.column == "created_at"
          db_present_model_absent << { :name => k, :category => :timestamp }
        elsif file.getForeignKeys.include? v.column
          db_present_model_absent << { :name => k, :category => :fk }
        elsif v.is_a? Length_constraint and (v.max_value == 255 or v.max_value >= 65535)
          db_present_model_absent << { :name => k, :category => :str_unlimited }
        elsif !file.contents.include? v.column
          db_present_model_absent << { :name => k, :category => :not_accessed }
        else
          db_present_model_absent << { :name => k, :category => :other }
        end
      end

      model_cons.each do |k, v|
        k2 = k.gsub("-#{Constraint::MODEL}", "-#{Constraint::DB}")
        column = file.getColumns[v.column]
        next if !column or db_cons[k2]

        if v.instance_of? Presence_constraint and !column.default_value
          model_present_db_absent << { :name => k, :category => :presence_no_default }
        elsif v.instance_of? Presence_constraint and column.default_value
          model_present_db_absent << { :name => k, :category => :presence_has_default }
        elsif v.instance_of? Format_constraint
          model_present_db_absent << { :name => k, :category => :format }
        elsif v.instance_of? Inclusion_constraint or v.instance_of? Exclusion_constraint
          model_present_db_absent << { :name => k, :category => :inclusion_exclusion }
        elsif v.instance_of? Uniqueness_constraint
          model_present_db_absent << { :name => k, :category => :unique }
        elsif v.instance_of? Customized_constraint or v.instance_of? Function_constraint
          model_present_db_absent << { :name => k, :category => :custom }
        else
          model_present_db_absent << { :name => k, :category => :other }
        end
      end
    end

    puts "absent_constraint\t#{@app_dir}\tdb_present_model_absent\tself_satisfied\t#{db_present_model_absent.select { |v| v[:category] == :self_satisfied }.count}"
    puts "absent_constraint\t#{@app_dir}\tdb_present_model_absent\tfk\t#{db_present_model_absent.select { |v| v[:category] == :fk }.count}"
    puts "absent_constraint\t#{@app_dir}\tdb_present_model_absent\tstr_unlimited\t#{db_present_model_absent.select { |v| v[:category] == :str_unlimited }.count}"
    puts "absent_constraint\t#{@app_dir}\tdb_present_model_absent\tnot_accessed\t#{db_present_model_absent.select { |v| v[:category] == :not_accessed }.count}"
    puts "absent_constraint\t#{@app_dir}\tdb_present_model_absent\tother\t#{db_present_model_absent.select { |v| v[:category] == :other }.count}"

    puts ""

    puts "absent_constraint\t#{@app_dir}\tmodel_present_db_absent\tpresence_no_default\t#{model_present_db_absent.select { |v| v[:category] == :presence_no_default }.count}"
    puts "absent_constraint\t#{@app_dir}\tmodel_present_db_absent\tpresence_default\t#{model_present_db_absent.select { |v| v[:category] == :presence_has_default }.count}"
    puts "absent_constraint\t#{@app_dir}\tmodel_present_db_absent\tformat\t#{model_present_db_absent.select { |v| v[:category] == :format }.count}"
    puts "absent_constraint\t#{@app_dir}\tmodel_present_db_absent\tinclusion_exclusion\t#{model_present_db_absent.select { |v| v[:category] == :inclusion_exclusion }.count}"
    puts "absent_constraint\t#{@app_dir}\tmodel_present_db_absent\tunique\t#{model_present_db_absent.select { |v| v[:category] == :unique }.count}"
    puts "absent_constraint\t#{@app_dir}\tmodel_present_db_absent\tcustom\t#{model_present_db_absent.select { |v| v[:category] == :custom }.count}"
    puts "absent_constraint\t#{@app_dir}\tmodel_present_db_absent\tother\t#{model_present_db_absent.select { |v| v[:category] == :other }.count}"
  end

  def compare_self
    # puts "@activerecord_files: #{@activerecord_files.length}"
    total_constraints = @activerecord_files.map { |k, v| v.getConstraints.length }.reduce(:+)
    db_cons_num = 0
    model_cons_num = 0
    html_cons_num = 0
    mm_cons_num = 0
    absent_cons = {}
    absent_cons2 = {}
    mm_cons_num2 = 0
    puts "mismatch_constraint\tAppDir\tConstraintType\tCategory\tKey\tMin1\tMax1\tMin2\tMax2\tMismatchFields"
    @activerecord_files.each do |key, file|
      constraints = file.getConstraints
      model_cons = constraints.select { |k, v| k.include? "-#{Constraint::MODEL}" }
      db_cons = constraints.select { |k, v| k.include? "-#{Constraint::DB}" }
      html_cons = constraints.select { |k, v| k.include? "-#{Constraint::HTML}" }
      model_cons_num += model_cons.length
      db_cons_num += db_cons.length
      html_cons_num += html_cons.length
      db_cons.each do |k, v|
        k2 = k.gsub("-#{Constraint::DB}", "-#{Constraint::MODEL}")
        k3 = k2.gsub("-#{v.class.name}-", "-#{Customized_constraint.to_s}-")
        puts "k2 #{k2}"
        begin
          column_name = v.column
          column = file.getColumns[column_name]
          db_filename = column.file_class.filename
        rescue
          column_name = "nocolumn"
          db_filename = "nofile"
        end
        next unless column # if the column doesn't exist
        next if column.is_deleted # if the column is deleted
        # if column is auto increment, then uniquness constraint and presence constraint are not needed in models
        if v.instance_of? Uniqueness_constraint or v.instance_of? Presence_constraint
          if column.auto_increment
            next
          end
        end
        # if column has default value, then the presence constraint is not needed.
        if v.instance_of? Presence_constraint
          if column.default_value
            next
          end
        end
        if model_cons[k3]
          puts "customized constraints"
          next
        end
        unless model_cons[k2]
          absent_cons[k] = v
          v.self_print
          puts "absent: #{column_name} #{v.table} #{db_filename} #{v.class.name} #{@commit}"
        else
          v2 = model_cons[k2]

          if not v.is_same_notype(v2)
            mismatch_category = "DB-Model"
            constraint_key = k2.gsub("-validate", "")
            db_min = (v.is_a? Length_constraint and v.min_value) ? v.min_value : ""
            db_max = (v.is_a? Length_constraint and v.max_value) ? v.max_value : ""
            model_min = (v2.is_a? Length_constraint and v2.min_value) ? v2.min_value : ""
            model_max = (v2.is_a? Length_constraint and v2.max_value) ? v2.max_value : ""
            mismatch_fields = compare_instance_variables(v, v2).reject { |a| a == "@type-db-validate" }

            mm_cons_num += 1

            puts "mismatch_constraint\t#{@app_dir}\t#{v.class.name}\t#{mismatch_category}\t#{constraint_key}\t#{db_min}\t#{db_max}\t#{model_min}\t#{model_max}\t#{mismatch_fields}"
          end
        end
      end

      model_cons.each do |k, v|
        k2 = k.gsub("-#{Constraint::MODEL}", "-#{Constraint::HTML}")
        puts "k2 #{k2}"
        begin
          column_name = v.column
          column = file.getColumns[column_name]
          model_filename = column.file_class.filename
        rescue
          column_name = "nocolumn"
          model_filename = "nofile"
        end
        unless html_cons[k2]
          absent_cons2[k] = v
          v.self_print
          puts "absent2: #{column_name} #{v.table} #{model_filename} #{v.class.name} #{@commit}"
        else
          v2 = html_cons[k2]

          if not v.is_same_notype(v2)
            mismatch_category = "Model-HTML"
            constraint_key = k2.gsub("-#{Constraint::HTML}", "")
            model_min = (v.is_a? Length_constraint and v.min_value) ? v.min_value : ""
            model_max = (v.is_a? Length_constraint and v.max_value) ? v.max_value : ""
            html_min = (v2.is_a? Length_constraint and v2.min_value) ? v2.min_value : ""
            html_max = (v2.is_a? Length_constraint and v2.max_value) ? v2.max_value : ""
            mismatch_fields = compare_instance_variables(v, v2).reject { |a| a == "@type-validate-html" }

            mm_cons_num2 += 1

            puts "mismatch_constraint\t#{@app_dir}\t#{v.class.name}\t#{mismatch_category}\t#{constraint_key}\t#{model_min}\t#{model_max}\t#{html_min}\t#{html_max}\t#{mismatch_fields}"
          end
        end
      end
    end
    compare_absent_constraints
    puts "total absent: #{absent_cons.size} total_constraints: #{total_constraints} model_cons_num: #{model_cons_num} db_cons_num: #{db_cons_num} mm_cons_num: #{mm_cons_num}"
    puts "total absent2: #{absent_cons2.size} total_constraints: #{total_constraints} html_cons_num: #{html_cons_num} model_cons_num: #{model_cons_num}  mm_cons_num2: #{mm_cons_num2}"
  end

  def column_stats
    num_column = 0
    num_column_has_constraints = 0
    @activerecord_files.each do |k, v|
      n, nh = v.num_columns_has_constraints
      num_column += n
      num_column_has_constraints += nh
    end
    return num_column, num_column_has_constraints
  end

  def build
    self.extract_files
    self.annotate_model_class
    self.extract_constraints
    self.print_columns
    self.calculate_loc
    puts "@active_files : #{@activerecord_files.size}"
  end

  def print_validate_functions
    all_functions = {}
    @activerecord_files.each do |key, file|
      functions = file.functions
      functions.each do |k, v|
        all_functions[k] = v
      end     
    end
    contents = ""       
    @activerecord_files.each do |key, file|
      ast = file.ast
      file.getConstraints.each do |k, constraint|
        if constraint.type == Constraint::MODEL
          if constraint.instance_of? Function_constraint
            funcname = constraint.funcname
            k = funcname
            v = all_functions[k]
            if v
              file.printFunction(k, v)
              contents += "====start of function #{k}====\n"
              contents += "#{v.source}\n"
              contents +="====end of function #{k}====\n"
            end
          end
        end
      end
    end
    return contents
  end

  def calculate_loc
    app_subdir = File.join(@app_dir, "app")
    db_subdir = File.join(@app_dir, "db")
    if app_dir.include? "spree"
      app_subdir = File.join(@app_dir, "*/app")
      db_subdir = File.join(@app_dir, "*/db")
    end
    output = `cloc --json #{app_subdir} #{db_subdir}`
    begin
      json_output = JSON.parse(output)

      ruby_loc = json_output.fetch("Ruby", {}).fetch("code", 0)
      erb_loc = json_output.fetch("ERB", {}).fetch("code", 0)
      haml_loc = json_output.fetch("Haml", {}).fetch("code", 0)
      html_loc = json_output.fetch("HTML", {}).fetch("code", 0)

      @loc = ruby_loc + erb_loc + haml_loc + html_loc
    rescue
      @loc = 0
    end
  end
end
