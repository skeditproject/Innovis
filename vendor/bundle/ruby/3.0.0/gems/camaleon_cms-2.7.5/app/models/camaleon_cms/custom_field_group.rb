module CamaleonCms
  class CustomFieldGroup < CamaleonCms::CustomField
    self.primary_key = :id
    # attrs required: name, slug, description
    alias_attribute :site_id, :parent_id

    default_scope do
      where.not(object_class: '_fields')
           .reorder("#{CamaleonCms::CustomField.table_name}.field_order ASC")
    end

    has_many :metas, -> { where(object_class: 'CustomFieldGroup') }, foreign_key: :objectid, dependent: :destroy
    has_many :fields, -> { where(object_class: '_fields') }, class_name: 'CamaleonCms::CustomField',
                                                             foreign_key: :parent_id, dependent: :destroy
    belongs_to :site, foreign_key: :parent_id, required: false

    validates_uniqueness_of :slug, scope: %i[object_class objectid parent_id]

    before_validation :before_validating

    # add fields to group
    # item:
    # -  sample:  {"name"=>"Label", "slug"=>"my_slug", "description"=>"my description (optional)"}
    # -  options (textbox sample):  {"field_key":"text_box","multiple":"1","required":"1",
    #     "translate":"1"}
    #   * field_key (string) | translate (boolean) | default_value (unique value) |
    #      default_values (array - multiple values for this field) | label_eval (boolean) |
    #      multiple_options (array)
    #   * multiple_options (used for select, radio and checkboxes ): [{"title"=>"Option Title",
    #      "value"=>"2", "default"=>"1"}, {"title"=>"abcde", "value"=>"3"}]
    #   * label_eval: (Boolean, default false), true => will evaluate the label and description of
    #       current field using (eval('my_label')) to have translatable|dynamic labels
    # ****** check all options for each case in Admin::CustomFieldsHelper ****
    # SAMPLE: my_model.add_field({"name"=>"Sub Title", "slug"=>"subtitle"}, {"field_key"=>"text_box",
    #   "translate"=>true, default_value: "Get in Touch"})
    def add_manual_field(item, options)
      c = get_field(item[:slug] || item['slug'])
      return c if c.present?

      field_item = fields.new(item)
      if field_item.save
        field_item.set_options(options)
        auto_save_default_values(field_item, options)
      end
      field_item
    end
    alias add_field add_manual_field

    # return a field with slug = slug from current group
    def get_field(slug)
      fields.find_by(slug: slug)
    end

    # only used by form on admin panel (protected)
    # return array of failed_fields and full_fields [[failed fields], [all fields]]
    def add_fields(items, item_options)
      fields.where.not(id: items.to_h.map { |_k, obj| obj['id'] }.uniq).destroy_all
      cache_fields = []
      order_index = 0
      errors_saved = []
      if items.present?
        items.each do |i, item|
          item[:field_order] = order_index
          options = item_options[i] || {}
          if item[:id].present? && (field_item = fields.find_by(id: item[:id])).present?
            saved = field_item.update(item)
            cache_fields << field_item
          else
            field_item = fields.new(item)
            cache_fields << field_item
            saved = field_item.save
            auto_save_default_values(field_item, options) if saved
            errors_saved << field_item unless saved
          end
          if saved
            field_item.set_meta('_default', options)
            order_index += 1
          end
        end
      end
      [errors_saved, cache_fields]
    end

    # generate the caption for this group
    def get_caption
      caption = ''
      begin
        case object_class
        when 'PostType_Post'
          caption = "Fields for Contents in <b>#{site.post_types.find(objectid).decorate.the_title}</b>"
        when 'PostType_Category'
          caption = "Fields for Categories in <b>#{site.post_types.find(objectid).decorate.the_title}</b>"
        when 'PostType_PostTag'
          caption = "Fields for Post tags in <b>#{site.post_types.find(objectid).decorate.the_title}</b>"
        when 'Widget::Main'
          caption = "Fields for Widget <b>(#{CamaleonCms::Widget::Main.find(objectid).name.translate})</b>"
        when 'Theme'
          caption = "Field settings for Theme <b>(#{begin
            site.themes.find(objectid).name
          rescue StandardError
            objectid
          end})</b>"
        when 'NavMenu'
          caption = "Field settings for Menus <b>(#{CamaleonCms::NavMenu.find(objectid).name})</b>"
        when 'Site'
          caption = 'Field settings the site'
        when 'PostType'
          caption = 'Fields for all <b>Post_Types</b>'
        when 'Post'
          p = CamaleonCms::Post.find(objectid).decorate
          caption = "Fields for content <b>(#{p.the_title})</b>"
        else # 'Plugin' or other class
          caption = "Fields for <b>#{object_class}</b>"
        end
      rescue StandardError => e
        Rails.logger.debug "Camaleon CMS - Menu Item Error: #{e.message} ==> Attrs: #{attributes}"
      end
      caption
    end

    private

    def before_validating
      self.slug = "_group-#{name.to_s.parameterize}" unless slug.present?
    end

    # auto save the default field values
    def auto_save_default_values(field, options)
      class_name = object_class.split('_').first
      return unless %w[Post Category Plugin
                       Theme].include?(class_name) && objectid && (options[:default_value].present? || options[:default_values].present?)

      owner = if class_name == 'Theme'
                "CamaleonCms::#{class_name}".constantize.find(objectid) # owner model
              else
                begin
                  "CamaleonCms::#{class_name}".constantize.find(objectid)
                rescue StandardError
                  "CamaleonCms::#{class_name}".constantize.find_by(slug: objectid)
                end
              end
      (options[:default_values] || [options[:default_value]] || []).each do |value|
        if owner.present?
          owner.custom_field_values.create!(custom_field_id: field.id, custom_field_slug: field.slug,
                                            value: fix_meta_value(value))
        end
      end
    end
  end
end
