require File.dirname(__FILE__) + '/lib/fast_xml_serializer'

ActiveRecord::Base.send(:include, FastXmlSerializer)
