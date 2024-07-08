class CamaleonCmsAwsUploader < CamaleonCmsUploader
  def after_initialize
    @cloudfront = @aws_settings[:cloud_front] || @current_site.get_option('filesystem_s3_cloudfront')
    @aws_region = @aws_settings[:region] || @current_site.get_option('filesystem_region', 'us-west-2')
    @aws_akey = @aws_settings[:access_key] || @current_site.get_option('filesystem_s3_access_key')
    @aws_asecret = @aws_settings[:secret_key] || @current_site.get_option('filesystem_s3_secret_key')
    @aws_bucket = @aws_settings[:bucket] || @current_site.get_option('filesystem_s3_bucket_name')
    @aws_settings[:aws_file_upload_settings] ||= ->(settings) { settings }
    @aws_settings[:aws_file_read_settings] ||= ->(data, _s3_file) { data }
  end

  def setup_private_folder
    return unless is_private_uploader?

    add_folder(PRIVATE_DIRECTORY)

    @aws_settings['inner_folder'] = "#{@aws_settings['inner_folder']}/#{PRIVATE_DIRECTORY}"
  end

  # recover all files from AWS and parse it to save into DB as cache
  def browser_files
    bucket.objects({ prefix: @aws_settings['inner_folder'].presence || nil }).each do |file|
      next if File.dirname(file.key).split('/').pop == 'thumb'

      cache_item(file_parse(file))
    end
  end

  # load media files from a specific folder path
  def objects(prefix = '/', sort = 'created_at')
    if @aws_settings['inner_folder'].present?
      prefix = "#{@aws_settings['inner_folder']}/#{prefix}".gsub('//', '/')
      prefix = prefix[0..-2] if prefix.end_with?('/')
    end
    super(prefix, sort)
  end

  def fetch_file(file_name)
    bucket.object(file_name).download_file(file_name) unless file_exists?(file_name)

    raise ActionController::RoutingError, 'File not found' unless file_exists?(file_name)

    file_name
  end

  # parse an AWS file into custom file_object
  def file_parse(s3_file)
    key = s3_file.is_a?(String) ? s3_file : s3_file.key
    key = key.cama_fix_media_key
    is_dir = s3_file.is_a?(String) || File.extname(key) == ''

    url = if is_private_uploader?
            is_dir ? '' : File.basename(key)
          elsif is_dir
            ''
          else
            (@cloudfront.present? ? File.join(@cloudfront, key) : s3_file.public_url)
          end

    res = {
      'name' => File.basename(key),
      'folder_path' => File.dirname(key),
      'url' => url,
      'is_folder' => is_dir,
      'file_size' => is_dir ? 0 : s3_file.size.round(2),
      'thumb' => '',
      'file_type' => is_dir ? '' : self.class.get_file_format(key),
      'created_at' => is_dir ? '' : s3_file.last_modified,
      'dimension' => ''
    }.with_indifferent_access
    if res['file_type'] == 'image' && File.extname(res['name']).downcase != '.gif'
      res['thumb'] =
        version_path(res['url']).sub('.svg',
                                     '.jpg')
    end
    res['key'] = File.join(res['folder_path'], res['name'])
    @aws_settings[:aws_file_read_settings].call(res, s3_file)
  end

  # add a file object or file path into AWS server
  # :key => (String) key of the file ot save in AWS
  # :args => (HASH) {same_name: false, is_thumb: false}, where:
  #   - same_name: false => avoid to overwrite an existent file with same key and search for an available key
  #   - is_thumb: true => if this file is a thumbnail of an uploaded file
  def add_file(uploaded_io_or_file_path, key, args = {})
    args = { same_name: false, is_thumb: false }.merge(args)
    res = nil
    key = "#{@aws_settings['inner_folder']}/#{key}" if @aws_settings['inner_folder'].present? && !args[:is_thumb]
    key = key.cama_fix_media_key
    key = search_new_key(key) unless args[:same_name]

    if @instance # private hook to upload files by different way, add file data into result_data
      _args = { result_data: nil, file: uploaded_io_or_file_path, key: key, args: args, klass: self }
      @instance.hooks_run('uploader_aws_before_upload', _args)
      return _args[:result_data] if _args[:result_data].present?
    end

    s3_file = bucket.object(key.slice(1..-1))
    s3_file.upload_file(
      uploaded_io_or_file_path.is_a?(String) ? uploaded_io_or_file_path : uploaded_io_or_file_path.path, @aws_settings[:aws_file_upload_settings].call({ acl: 'public-read' })
    )
    res = cache_item(file_parse(s3_file)) unless args[:is_thumb]
    res
  end

  # add new folder to AWS with :key
  def add_folder(key)
    key = "#{@aws_settings['inner_folder']}/#{key}" if @aws_settings['inner_folder'].present?
    key = key.cama_fix_media_key
    s3_file = bucket.object(key.slice(1..-1) << '/')
    s3_file.put(body: nil)
    cache_item(file_parse(s3_file))
  end

  # delete a folder in AWS with :key
  def delete_folder(key)
    key = "#{@aws_settings['inner_folder']}/#{key}" if @aws_settings['inner_folder'].present?
    key = key.cama_fix_media_key
    bucket.objects(prefix: key.slice(1..-1) << '/').delete
    get_media_collection.find_by_key(key).take.destroy
  end

  # delete a file in AWS with :key
  def delete_file(key)
    key = "#{@aws_settings['inner_folder']}/#{key}" if @aws_settings['inner_folder'].present?
    key = key.cama_fix_media_key
    begin
      bucket.object(key.slice(1..-1)).delete
    rescue StandardError
      ''
    end
    @instance.hooks_run('after_delete', key)
    get_media_collection.find_by_key(key).take.destroy
  end

  # initialize a bucket with AWS configurations
  # return: (AWS Bucket object)
  def bucket
    @bucket ||= lambda {
      Aws.config.update({ region: @aws_region, credentials: Aws::Credentials.new(@aws_akey, @aws_asecret) })
      s3 = Aws::S3::Resource.new
      s3.bucket(@aws_bucket)
    }.call
  end
end
