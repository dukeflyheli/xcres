require 'xcresources/builder/file_builder'
require 'xcresources/helper/file_helper'

class XCResources::ResourcesBuilder < XCResources::FileBuilder

  include XCResources::FileHelper

  COMPILER_KEYWORDS = %w{
    auto, break, case, char, const, continue, default, do, double, else, enum, extern, float, for, goto, if, inline,
    int, long, register, restrict, return, short, signed, sizeof, static, struct, switch, typedef, union, unsigned,
    void, volatile, while
  }

  # @return [String]
  #         the name of the constant in the generated file(s)
  attr_accessor :resources_constant_name

  # @return [Bool]
  #         whether the generated resources constant should contain inline
  #         documentation for each key, true by default
  attr_accessor :documented
  alias :documented? :documented

  # Initialize a new instance
  #
  def initialize
    @sections = {}
    self.documented = true
  end

  # Extract resource name from #output_path, if not customized
  #
  # @return [String]
  #
  def resources_constant_name
    @resources_constant_name ||= basename_without_ext output_path
  end

  def add_section name, items, options = []
    raise ArgumentError.new 'No items given!' if items.nil?

    transformed_items = {}

    for key, value in items
      transformed_key = transform_key key, options

      # Skip invalid key names
      if transformed_key.length == 0
        logger.warn "Skip invalid key: '%s'. (Was transformed to empty text)", key
        next
      end

      # Skip compiler keywords
      if COMPILER_KEYWORDS.include? transformed_key
        logger.warn "Skip invalid key: '%@'. (Was transformed to keyword '%s')", key, transformed_key
        next
      end

      transformed_items[transformed_key] = value
    end

    @sections[name] = transformed_items
  end

  def build
    super

    # Build file contents and write them to disk
    write_file "#{output_path}.h", (build_contents do |h_file|
      build_header_contents h_file
    end)

    write_file "#{output_path}.m", (build_contents do |m_file|
      build_impl_contents m_file
    end)
  end

  protected

    def transform_key key, options
      # Split the key into components
      components = key.underscore.split /[_\/ ]/

      # Build the new key incremental
      result = ''

      for component in components
        # Ignore empty components
        next unless component.length > 0

        # Ignore components which are already contained in the key, if enabled
        if options[:shorten_keys]
          next unless key.downcase.scan(component).blank?
        end

        # Clean component from non alphanumeric characters
        clean_component = component.gsub /[^a-zA-Z0-9]/, ''

        # Skip if empty
        next unless clean_component.length > 0

        if result.length == 0
          result += clean_component
        else
          result += clean_component[0].upcase + clean_component[1..-1]
        end
      end

      result
    end

    def build_header_contents h_file
      h_file.writeln 'const struct %s {' % resources_constant_name
      h_file.section do |struct|
        enumerate_sections do |section_key, enumerate_keys|
          struct.writeln 'struct %s {' % section_key
          struct.section do |section_struct|
            enumerate_keys.call do |key, value, comment|
              if documented?
                section_struct.writeln '/// %s' % (comment || value) #unless comment.nil?
              end
              section_struct.writeln '__unsafe_unretained NSString *%s;' % key
            end
          end
          struct.writeln '} %s;' % section_key
        end
      end
      h_file.writeln '} %s;' % resources_constant_name
    end

    def build_impl_contents m_file
      m_file.writeln 'const struct %s %s = {' % [resources_constant_name, resources_constant_name]
      m_file.section do |struct|
        enumerate_sections do |section_key, enumerate_keys|
          struct.writeln '.%s = {' % section_key
          struct.section do |section_struct|
            enumerate_keys.call do |key, value|
              section_struct.writeln '.%s = @"%s",' % [key, value]
            end
          end
          struct.writeln '},'
        end
      end
      m_file.writeln '};'
    end

    def enumerate_sections
      # Iterate sections ordered by key
      for section_key, section_content in @sections.sort
        # Pass section key and block to yield the keys ordered
        proc = Proc.new do |&block|
          for key, value in section_content.sort
            if value.is_a? Hash
              block.call key, value[:value], value[:comment]
            else
              block.call key, value, nil
            end
          end
        end
        yield section_key, proc
      end
    end

end
