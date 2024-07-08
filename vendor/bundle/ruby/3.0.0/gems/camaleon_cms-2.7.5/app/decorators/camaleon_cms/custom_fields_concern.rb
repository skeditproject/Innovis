module CamaleonCms
  module CustomFieldsConcern
    # ======================CUSTOM FIELDS=====================================
    # render as html the custom fields marked for frontend
    def render_fields
      object.cama_fetch_cache('render_fields') do
        h.controller.render_to_string(partial: 'partials/render_custom_field',
                                      locals: { fields: object.get_fields_object(true) })
      end
    end

    # return custom field content with key field_key
    # translated and short codes evaluated like the content
    # default_val: default value returned when this field was not registered
    def the_field(field_key, default_val = '')
      h.do_shortcode(object.get_field(field_key, default_val).to_s.translate(@_deco_locale), object)
    end
    alias the_field! the_field

    # return custom field contents with key field_key
    # translated and short codes evaluated like the content
    # this is for multiple values
    def the_fields(field_key)
      r = []
      object.get_fields(field_key).each do |text|
        r << h.do_shortcode(text.to_s.translate(@_deco_locale), object)
      end
      r
    end

    # the same function as get_fields_grouped(..) but this returns translated and shortcodes evaluated
    def the_fields_grouped(field_keys, is_json_format = false, single_value = false)
      res = []
      object.get_fields_grouped(field_keys).each do |_group|
        group = {}.with_indifferent_access
        _group.each_key do |k|
          group[k] = if is_json_format
                       _group[k].map { |v| parse_html_json(v) }
                     else
                       _group[k].map { |v| h.do_shortcode(v.to_s.translate(@_deco_locale), object) }
                     end
          group[k] = group[k].first if single_value
        end
        res << group
      end
      res
    end

    # the same function as get_fields_grouped(..) but this returns translated and shortcodes evaluated
    def the_field_grouped(field_key, is_json_format = false, is_multiple = false)
      the_fields_grouped([field_key], is_json_format).map do |v|
        is_multiple ? v.values.first : v.values.try(:first).try(:first)
      end
      # the_fields_grouped([field_key], is_json_format).map{|v| is_multiple ? v.values.first : v.values.first }
    end

    # return custom field contents with key field_key (only for type attributes)
    # translated and short codes evaluated like the content
    # this is for multiple values
    def the_json_fields(field_key)
      r = []
      object.get_fields(field_key).each do |text|
        r << parse_html_json(text)
      end
      r
    end
    alias the_attribute_fields the_json_fields

    # return custom field content with key field_key (only for type attributes)
    # translated and short codes evaluated like the content
    # default_val: default value returned when this field was not registered
    def the_json_field(field_key, default_val = '')
      parse_html_json(object.get_field(field_key, default_val))
    end
    alias the_attribute_field the_json_field

    private

    def parse_html_json(json)
      r = JSON.parse(json || '{}').with_indifferent_access
      r.each_key do |k|
        r[k] = h.do_shortcode(r[k].to_s.translate(@_deco_locale), object)
      end
      r
    end
  end
end
