# Copyright:: Copyright 2009 Google Inc.
# License:: All Rights Reserved.
# Original Author:: Mark Roach (mailto:mrroach@google.com)
#
# Unit tests for the FastXmlSerializer extension.
#
# $Id:$

require File.dirname(__FILE__) + '/../test_helper'
require 'xml'

class FastXmlSerializerTest < ActiveSupport::TestCase

  context 'an ActiveRecord subclass' do

    setup do
      ActiveRecord::Base.connection.create_table('records') do |table|
        table.string :name
        table.string :short_description
        table.integer :owner_id
        table.datetime :created_at
      end

      ActiveRecord::Base.connection.create_table('owners') do |table|
        table.string :name
        table.datetime :created_at
      end

      ActiveRecord::Base.connection.create_table('tags') do |table|
        table.string :name
        table.integer :record_id
        table.datetime :created_at
      end

      ActiveRecord::Base.connection.create_table('flags') do |table|
        table.string :name
        table.boolean :disabled
      end


      Object.const_set(:Owner, Class.new(ActiveRecord::Base))

      Object.const_set(:Tag, Class.new(ActiveRecord::Base))

      Object.const_set(:Record, Class.new(ActiveRecord::Base))

      Object.const_set(:Flag, Class.new(ActiveRecord::Base))
      Record.belongs_to(:owner)
      Record.has_many(:tags)
      Tag.belongs_to(:record)
    end

    teardown do
      Object.send(:remove_const, :Record)
      Object.send(:remove_const, :Owner)
      Object.send(:remove_const, :Tag)
      Object.send(:remove_const, :Flag)
    end

    should 'return array of column info for xml_serialization_fields' do
      assert_same_elements(
          [['short_description', 'short-description', :string],
           ['id', 'id', :integer], ['name', 'name', :string],
           ['owner_id', 'owner-id', :integer],
           ['created_at', 'created-at', :datetime]],
          Record.xml_serialization_fields)
    end

    context 'instances_to_xml' do
      setup do
        @instances = (1..3).map do |i|
          instance = Record.new(:name => "instance#{i}",
              :short_description => "Description of #{i}")
          instance.id = i
          instance
        end
      end

      should 'return activesupport deserializable xml' do
        hash = Hash.from_xml(Record.instances_to_xml(@instances))
        assert_same_elements(['instance1', 'instance2', 'instance3'],
                             hash['records'].map { |rec| rec['name'] })
      end

      should 'honor :only option' do
        hash = Hash.from_xml(
            Record.instances_to_xml(@instances, :only => [:id]))
        assert_same_elements [1, 2, 3], hash['records'].map { |rec| rec['id'] }
        assert_same_elements([nil, nil, nil],
                             hash['records'].map { |rec| rec['name'] })
      end

      should 'honor :root option' do
        hash = Hash.from_xml(
            Record.instances_to_xml(@instances, :root => 'foos'))
        assert_equal 3, hash['foos'].size
      end

      should 'honor :document option' do
        document = XML::Document.new
        Record.instances_to_xml(@instances, :document => document)
        assert_equal 'records', document.root.name
        assert_equal 3, document.root.children.size
      end

      should 'honor :parent option' do
        document = XML::Document.new
        document.root = XML::Node.new('parent')
        Record.instances_to_xml(@instances, :parent => document.root)
        assert_equal 'records', document.root.children.first.name
        assert_equal 3, document.root.children.first.children.size
      end
    end

    context '#to_xml_doc' do
      should 'return an xml doc with root name matching class' do
        record = Record.new(:name => 'testrecord')
        assert_equal 'record', record.to_xml_doc.root.name
      end

      should 'return an xml doc with elements matching columns' do
        record = Record.new(:name => 'testrecord')
        assert_same_elements(
            ['name', 'short-description', 'id', 'created-at', 'owner-id'],
            record.to_xml_doc.root.map(&:name))
      end

      should 'return an xml doc with elements including methods' do
        record = Record.new(:name => 'testrecord')
        flexmock(record).should_receive(:method_foo).and_return('foovar')
        flexmock(Record).should_receive(:xml_serialization_methods).
              and_return([['method_foo', 'method-foo', :string]])
        values = record.to_xml_doc.root.inject({}) do |hash,element|
          hash[element.name] = element.content
          hash
        end
        assert_include 'method-foo', values
      end

      should 'return an xml doc with values matching instance' do
        record = Record.new(:name => 'testrecord',
                                   :short_description => 'A test object')
        record.id = 6
        values = record.to_xml_doc.root.inject({}) do |hash,element|
          hash[element.name] = element.content
          hash
        end
        assert_equal({'name' => 'testrecord',
                      'short-description' => 'A test object',
                      'id' => '6',
                      'owner-id' => '',
                      'created-at' => ''},
                      values)
      end

      should 'return an xml doc with types matching instance' do
        record = Record.new(:name => 'testrecord',
                                   :short_description => 'A test object',
                                   :created_at => '2009-10-14 12:00:00 UTC',
                                   :owner_id => 12)
        record.id = 6
        values = record.to_xml_doc.root.inject({}) do |hash,element|
          hash[element.name] = element['type']
          hash
        end
        assert_equal({'name' => nil,
                      'short-description' => nil,
                      'id' => 'integer',
                      'owner-id' => 'integer',
                      'created-at' => nil},
                      values)
      end

      should 'honor :root_node option' do
        document = XML::Document.new
        document.root = XML::Node.new('aggregate')
        record = Record.new(:name => 'testrecord')
        record.to_xml_doc(:root_node => document.root,
                          :fields => [['name', 'name', 'string']])
        assert_equal 'name', document.root.children.first.name
        assert_equal 'testrecord', document.root.children.first.content
      end

      should 'honor :include option to add belongs_to association data' do
        owner = Owner.new(:name => 'owner')
        record = Record.new(:owner => owner)
        result = Hash.from_xml(record.to_xml_doc(:include => [:owner]).to_s)
        assert_equal({'name' => 'owner',
                      'id' => nil,
                      'created_at' => nil},
                      result['record']['owner'])
      end

      should 'honor :include option to add has_many association data' do
        tag1 = Tag.new(:name => 'useless')
        tag2 = Tag.new(:name => 'trash')
        record = Record.new(:tags => [tag1, tag2])
        result = Hash.from_xml(record.to_xml_doc(:include => [:tags]).to_s)
        assert_equal([{'name' => 'useless', 'id' => nil,
                       'created_at' => nil, 'record_id' => nil},
                      {'name' => 'trash', 'id' => nil,
                       'created_at' => nil, 'record_id' => nil}],
                      result['record']['tags'])
      end

      should 'honor array of :include options' do
        owner = Owner.new(:name => 'owner')
        tag1 = Tag.new(:name => 'useless')
        tag2 = Tag.new(:name => 'trash')
        record = Record.new(:tags => [tag1, tag2], :owner => owner)
        result = Hash.from_xml(record.to_xml_doc(:include => [:tags,
                                                              :owner]).to_s)
        assert_equal([{'name' => 'useless', 'id' => nil,
                       'created_at' => nil, 'record_id' => nil},
                      {'name' => 'trash', 'id' => nil,
                       'created_at' => nil, 'record_id' => nil}],
                      result['record']['tags'])
        assert_equal({'name' => 'owner',
                      'id' => nil,
                      'created_at' => nil},
                      result['record']['owner'])
      end

      should 'honor nested :include options' do
        owner = Owner.new(:name => 'owner')
        record = Record.new(:owner => owner)
        tag = Tag.new(:name => 'tag', :record => record)
        doc = tag.to_xml_doc(:include => [{:record => {:include => [:owner]}}])
        result = Hash.from_xml(doc.to_s)
        assert_equal 'owner', result['tag']['record']['owner']['name']
      end

      should 'raise error on invalid :include options' do
        owner = Owner.new(:name => 'owner')
        record = flexmock(Record.new(:owner => owner))
        record.should_receive(:ruin_everything).never
        assert_raise FastXmlSerializer::InvalidInclude do
          record.to_xml_doc(:include => [:owner, :ruin_everything]).to_s
        end
      end

      should 'insert a nil attribute for nil association' do
        record = Record.new()
        doc = record.to_xml_doc(:include => [:owner])
        result = Hash.from_xml(doc.to_s)
        assert_include 'owner', result['record']
        assert_nil result['record']['owner']
      end

      should 'return an xml doc with nil attribute set' do
        record = Record.new(:short_description => 'A test object')
        values = record.to_xml_doc.root.inject({}) do |hash,element|
          hash[element.name] = element['nil']
          hash
        end
        assert_equal({'name' => 'true',
                      'short-description' => nil,
                      'id' => 'true',
                      'created-at' => 'true',
                      'owner-id' => 'true'},
                      values)

      end

      should 'handle boolean values' do
        record = Flag.new(:disabled => false)
        xml = record.to_xml_doc.to_s
        assert_equal false, Hash.from_xml(xml)['flag']['disabled']
      end
    end
  end
end
