require 'yaml'
require 'fileutils'
require 'securerandom'

BUILD_DIR ="#{Dir.pwd}/build"

module Shipwright
  class Builder

    def initialize
      @base_files_hash = {}
      @stage_uuid_hash = Hash.new({})
      @pipeline_ids = {}
    end

    def clean_build_dir
      if File.exist?(BUILD_DIR)
        FileUtils.remove_dir(BUILD_DIR)
      end
      Dir.mkdir(BUILD_DIR)
    end

    def load_base_files(destination_hash, hash_key, path)
      destination_hash[hash_key] = {} if destination_hash[hash_key].nil?

      base_files = Dir[path]
      base_files.each do|base_file|
        file_name = base_file.split('/')[-1].gsub('.json', '')
        destination_hash[hash_key][file_name] = IO.read(base_file)
      end
    end

    def render_template(
      app_name:,
      region: nil,
      template_string:,
      region_template_vars: nil,
      app_template_vars: nil,
      output_name: nil,
      triggers: nil,
      notifications: nil,
      account_id: nil,
      pipeline_name:
    )
        rendered_template = template_string.clone
        pipeline_id = SecureRandom.uuid()
        pipeline_key = "#{app_name}-#{pipeline_name}"
        if region
          pipeline_key = "#{app_name}-#{pipeline_name}-#{region}"
        end
        # currently overrides multi-region ids
        # need to enable and fix the multi-region trigger pipeline id finding
        # if output_name
        #   pipeline_key = "#{app_name}-#{pipeline_name}-#{output_name}"
        # end
        puts "\trendering #{pipeline_key}"

        @pipeline_ids[pipeline_key] = pipeline_id

        rendered_template.gsub!('$$PIPELINE_UUID', pipeline_id)
        rendered_template.gsub!('$$SERVICE_NAME', app_name)
        rendered_template.gsub!('$$PIPELINE_NAME_PREFIX', "#{app_name}-managed")
        rendered_template.gsub!('$$REGION', region) unless region.nil?
        rendered_template.gsub!('$$ACCOUNT_ID', account_id) unless account_id.nil?

        unless region_template_vars.nil?
          region_template_vars.each do |template_var|
            rendered_template.gsub!("$$#{template_var['key']}", "#{template_var['value']}")
          end
        end

        unless app_template_vars.nil?
          app_template_vars.each do |template_var|
            rendered_template.gsub!("$$#{template_var['key']}", "#{template_var['value']}")
          end
        end

        unless triggers.nil?
          triggers.each do |trigger|
            # find pipeline id dynamically?

            # TODO: once we have typed triggers and pipeline modles we can be smarter about how we build that json
            # app can be a string
            if trigger['type'] == 'pipeline'
              rendered_template.gsub!('$$TRIGGER_APP_VALUE', trigger['application'])

              trigger_key = "#{trigger['application'].gsub('-managed', '')}-#{trigger['pipeline']}"
              if trigger['region']
                trigger_key = "#{trigger_key}-#{trigger['region']}"
              end

              pipeline_id = @pipeline_ids[trigger_key]
              rendered_template.gsub!('$$TRIGGER_PIPELINE_UUID', pipeline_id)
            end
            if trigger['type'] == 'pubsub'
              # TODO: assuming the pusub has the service name, and JUST using that seems weird here
            end
          end
        end

        unless notifications.nil?
          notifications.each do |notification|

          end
        end

        rendered_template
    end

    def render_and_write(pipeline_config:, path:, template_name:, project_name:, app_name:, app_template_vars: nil)
      if path.end_with?(template_name)
        template_string = IO.read(path)

        if pipeline_config['regions']
          pipeline_config['regions'].each do |region|
            # maybe just append account name?
            output_name = "#{template_name.gsub('.json', '')}-#{region['name']}.json"
            if region['outputName']
              output_name = "#{region['outputName']}"
            end
            output_path = "#{BUILD_DIR}/#{project_name}/#{app_name}/#{output_name}"

            output_file = Dir[output_path]

            unless output_file.size > 0
              rendered_template = render_template(
                app_name: app_name,
                region: region['name'],
                template_string: template_string,
                region_template_vars: region['template_vars'],
                app_template_vars: app_template_vars,
                output_name: output_name,
                triggers: pipeline_config['triggers'],
                account_id: region['account'],
                pipeline_name: pipeline_config['name']
              )

              File.open(output_path, 'w') { |file| file.write(rendered_template) }
            else
              # TODO: error for existing file for that region + env without unique outputName
            end
          end
        else
          # maybe just append account name?
          output_path = "#{BUILD_DIR}/#{project_name}/#{app_name}/#{template_name}"
          output_file = Dir[output_path]

          unless output_file.size > 0
            rendered_template = render_template(
              app_name: app_name,
              template_string: template_string,
              app_template_vars: app_template_vars,
              triggers: pipeline_config['triggers'],
              pipeline_name: pipeline_config['name']
            )

            File.open(output_path, 'w') { |file| file.write(rendered_template) }
          else
            # we hit this when we're looping through project base and overall base that exist from app or project overrides
          end
        end
      end
    end

    # get project dirs
    # for each
    #   load yardfile
    #   for each template look in app dir, project base, then overall base
    def render_and_write_templates
      clean_build_dir()

      yard_file_hash = {}

      Dir.glob("#{Dir.pwd}/projects/*").select { |f| File.directory? f }.each do|project_dir|
        yard_file = "#{project_dir}/yard.yaml"

        unless yard_file.empty?
          yard = YAML::load_file(yard_file)
          next if yard['disabled']

          apps = yard['apps']
          project_name = yard['project']['name']
          project_pipelines = yard['pipelines']

          Dir.mkdir "#{BUILD_DIR}/#{project_name}"
          puts project_name

          apps.each do |app_name, app_config|
            Dir.mkdir("#{BUILD_DIR}/#{project_name}/#{app_name}/")
            app_pipelines = Hash.new({})

            project_pipelines.each do |pipeline|
              app_pipelines[pipeline['name']] = app_pipelines[pipeline['name']].merge(pipeline)
            end

            unless app_config.nil? || app_config['pipelines'].nil?
              app_config['pipelines'].each do |pipeline|
                app_pipelines[pipeline['name']] = app_pipelines[pipeline['name']].merge(pipeline)
              end
            end

            # puts app_pipelines

            base_files = Dir["#{Dir.pwd}/base/*"]
            project_base_files = Dir["#{project_dir}/base/*"]
            app_files = Dir["#{project_dir}/#{app_name}/*"]

            app_pipelines.each do|pipeline_name, pipeline_config|
              template_name = pipeline_config['templateName'] ? pipeline_config['templateName'] : "#{pipeline_name}.json"

              app_files.each do|path|
                render_and_write(
                  pipeline_config: pipeline_config,
                  path: path,
                  template_name: template_name,
                  app_name: app_name,
                  project_name: project_name
                )
              end
              project_base_files.each do|path|
                render_and_write(
                  pipeline_config: pipeline_config,
                  path: path,
                  template_name: template_name,
                  app_name: app_name,
                  project_name: project_name,
                  app_template_vars: app_config['template_vars']
                )
              end

              base_files.each do|path|
                render_and_write(
                  pipeline_config: pipeline_config,
                  path: path,
                  template_name: template_name,
                  app_name: app_name,
                  project_name: project_name,
                  app_template_vars: app_config['template_vars']
                )
              end
            end
          end
        end
      end
    end
  end
end


