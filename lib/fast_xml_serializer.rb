# Author:: Mark Roach (mailto:mrroach@google.com)
#
# Copyright 2009 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'xml'

module FastXmlSerializer
  def self.included(base)
    base.extend(ClassMethods)
    base.send(:include, InstanceMethods)
  end

  class InvalidInclude < ArgumentError
  end

  module ClassMethods
    # Return a list of [name, xml-name, type] lists for serialization.
    #
    def xml_serialization_fields
      @xml_serialization_fields ||=
          columns_hash.map { |name,col| [name, name.dasherize, col.type] }
    end

    # Return a list of [name, xml-name, type] lists for serialization.
    #
    def xml_serialization_methods
      @xml_serialization_methods ||= []
    end

    def xml_element_name
      @xml_element_name ||= name.underscore.dasherize
    end
    # Build an XML::Document for the given child instances.
    #
    # Args:
    # - instances: An array of records to serialize.
    # - options: A hash of optional parameters:
    #   :root - The root xml node name (or nil to use the class name).
    #   :document - An XML::Document object (or nil and one will be created).
    #   :parent - An XML::Node object (or nil and one will be created).
    #   :only - An array of column names. Only the given columns will be
    #           serialized.
    #   :indent - Whether generated xml should be indented (default false).
    #   (any other options will be passed through to to_xml_doc)
    #
    # Returns:
    # - An xml string.
    #
    def instances_to_xml(instances, options={})
      options = options.dup
      if options[:root]
        node_name = options[:root].singularize
      else
        node_name = xml_element_name
        options[:root] = node_name.pluralize
      end
      root_node = XML::Node.new(options[:root])
      if options[:parent]
        options[:parent] << root_node
      else
        options[:document] ||= XML::Document.new
        options[:document].root = root_node
      end
      root_node['type'] = 'array'
      if options[:only]
        options[:fields] = xml_serialization_fields.select do |col|
          options[:only].include?(col[0].to_sym)
        end
      end
      instances.each do |instance|
        instance.to_xml_doc(
            options.merge(:parent => root_node,
                          :root => node_name))
      end
      if options[:document]
        options[:document].to_s(:indent => options.fetch(:indent, false))
      end
    end
  end

  module InstanceMethods
    # Serialize the record to an xml document.
    #
    # Args:
    # - options: A hash of optional parameters:
    #   :document - An XML::Document object (or nil and one will be created).
    #   :parent - An XML::Node object (or nil and one will be created).
    #   :root_node - An XML::Node object (or nil and one will be created).
    #   :fields - A list of [name, xml_name, type] lists of fields to serialize
    #            defaults to class.xml_serialization_fields.
    #   :methods - A list of [name, xml_name, type] lists of methods to
    #              include in the serialization.
    #   :include - A list of associations to serialize along with this record
    #   :root - The name of the root node for this record.
    #
    # Returns:
    # - An XML::Document object.
    #
    def to_xml_doc(options={})
      node_name = options[:root] || self.class.xml_element_name
      document = nil
      if options[:root_node]
        root_node = options[:root_node]
      else
        root_node = XML::Node.new(node_name)
        if options[:parent]
          options[:parent] << root_node
        else
          document = options[:document] || XML::Document.new
          document.root ||= root_node
          root_node = document.root
        end
        if options[:root] and options[:root] != self.class.xml_element_name
          root_node['type'] = self.class.name
        end
      end
      columns = options[:fields] || self.class.xml_serialization_fields
      methods = options[:methods] || self.class.xml_serialization_methods
      columns += methods if methods
      columns.each do |col_name,xml_name,col_type|
        root_node << construct_column_xml(col_name, xml_name, col_type)
      end
      if options[:include]
        options[:include].each do |assoc|
          construct_include_xml(root_node, options, assoc)
        end
      end
      document
    end

    private
    # Creates a new XML::Node for a column in a model.
    #
    # Args:
    # - col_name: the name of the column of data to work on
    # - xml_name: the name of the representation of the column in xml
    # - col_type: type of the column data
    #
    # Returns:
    # - An XML::Node object
    #
    def construct_column_xml(col_name, xml_name, col_type)
      node = XML::Node.new(xml_name)
      if col_type == :datetime
        # micro-optimization to avoid creating the datetime object
        value = self.send("#{col_name}_before_type_cast")
      else
        value = self.send(col_name)
      end
      if !value.nil?
        node << value
        node['type'] = col_type.to_s if [:integer, :boolean].include?(col_type)
      else
        node['nil'] = 'true'
      end
      return node
    end

    # Creates new XML::Node or Nodes for an associated model.
    #
    # Args:
    # - root_node: an XML::Node to attach the new node(s) to
    # - options: options hash given for XML generation
    # - assoc: name of the association to include
    #
    # Returns:
    # - Nothing. This will update the root_node given.
    #
    def construct_include_xml(root_node, options, assoc)
      nested_options = options.except(:fields, :include, :root_node)
      if assoc.kind_of?(Hash)
        assoc, child_options = assoc.entries.first
        nested_options.merge!(child_options)
      end
      # Make sure that this is really an association
      unless reflection = self.class.reflect_on_association(assoc)
        raise InvalidInclude.new(
            "#{self.class.name} has no #{assoc} association")
      end
      data = self.send(assoc)
      nested_options[:parent] = root_node
      nested_options[:root] = assoc.to_s.dasherize
      if data.respond_to?(:each)
        reflection.klass.send(:instances_to_xml, data, nested_options)
      elsif data
        data.to_xml_doc(nested_options)
      else
        # Add a nil value
        root_node << construct_column_xml(assoc, assoc.to_s.dasherize, :assoc)
      end
    end
  end
end
