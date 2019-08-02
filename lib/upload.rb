require 'swagger_client'
require 'json'
require 'faraday'

BUILD_DIR ="#{Dir.pwd}/build"

module Shipwright
  class Uploader
    def initialize
      token = ENV['GCLOUD_TOKEN']
      gate_host = 'https://gate-spinnaker.prod.gcp.openx.org' || ENV['GATE_HOST']

      response = Faraday.get("#{gate_host}/login") do|req|
        req.headers['Authorization'] = "Bearer #{token}"
      end

      if response.status != 302
        puts "#{response.status} for #{gate_host}"
        exit()
      end
      if response.headers['set-cookie'].nil?
        puts "cookie not found in headers"
        exit()
      end

      @config = SwaggerClient::Configuration.new
      @config.host = gate_host.split('//')[1]
      @config.scheme = gate_host.split(':')[0]
      @config.debugging = true

      api_client = SwaggerClient::ApiClient.new(@config)
      api_client.default_headers = {
        'Content-Type' => 'application/json',
        'User-Agent' => @user_agent,
        'Cookie' => response.headers['set-cookie'].split(' ')[0]
      }

      @apps_client = SwaggerClient::ApplicationControllerApi.new(api_client)
      @projects_client = SwaggerClient::ProjectControllerApi.new(api_client)
      @pipeline_client = SwaggerClient::PipelineControllerApi.new(api_client)
      @task_client = SwaggerClient::TaskControllerApi.new(api_client)
      @canary_config_client = SwaggerClient::V2CanaryConfigControllerApi.new(api_client)

      # figs = @canary_config_client.get_canary_configs_using_get()
      # puts figs

      # puts @canary_config_client.get_canary_config_using_get('0f61c71e-d719-4fe4-b346-4a20ff4879d0')

      # exit()

      @project_hash = {}
      @app_task_hash = {}

      @projects = @projects_client.all_using_get3()
      @apps = @apps_client.get_all_applications_using_get()

      # puts @apps
      # exit()
    end

    # TODO: can run these in parallel for simmilar types
    def wait_until_task_completes(task_config)
      while task_config[:status] === 'RUNNING' do
        sleep(2)
        task_response = @task_client.get_task_using_get1(task_config[:task_id])
        task_status = task_response[:status]

        task_config[:status] = task_status
      end
    end

    def create_project(project, upsert = false)
      project_name = project[:name]

      existing_project = @projects.select{|existing_project| existing_project[:name] == project_name }
      puts "exising"
      puts existing_project

      if !existing_project.empty? && upsert
        @config.logger.debug("project #{project_name} exists, setting project id")
        project['id'] = existing_project.first[:id]
      else
        puts "project #{project_name} doesnt exist"
      end
      puts "project here"
      puts project

      if @project_hash[project_name].nil? || upsert
        task_response = @task_client.task_using_post1({
            "job":         [{
              "type": "upsertProject",
              "project": project
            }],
            "application": "spinnaker",
            "project": project_name,
            "description": "Create Project #{project_name}"
          })

        @project_hash[project_name] = {
          task_id: task_response[:ref].split('/')[-1],
          status: 'RUNNING'
        }
      end

      wait_until_task_completes(@project_hash[project_name])
    end

    def create_application(app, project_name = nil)
      app_name = app[:name]

      existing_app = @apps.select{|existing_app| existing_app[:name] == app_name }

      # unless .empty?
        # TODO: implement app upserts
        @config.logger.debug("app #{app_name} exists, not modifying")
        # return
      app['id'] = existing_app.first['id']
      # else
      #   puts "#{app_name} doesnt exist, creating"
      # end

      # if @app_task_hash[app_name].nil?
        task_response = @task_client.task_using_post1({
          "job":         [{
            "type": "createApplication",
            "application": app
          }],
          "application": app_name,
          "description": "Create Application"
        })

        @app_task_hash[app_name] = {
          task_id: task_response[:ref].split('/')[-1],
          status: 'RUNNING'
        }
      # end

      wait_until_task_completes(@app_task_hash[app_name])
    end

    def create_pipeline(pipeline_string)
      pipeline_json = JSON.parse(pipeline_string)

      puts "creating pipeline #{pipeline_json['name']}"
      begin
        @pipeline_client.save_pipeline_using_post(pipeline_string)
      rescue SwaggerClient::ApiError => e
        puts "error #{e}"


        @pipeline_client.delete_pipeline_using_delete(pipeline_json['application'], pipeline_json['name'])
        @pipeline_client.save_pipeline_using_post(pipeline_string)

        # pipeline_client.update_pipeline_using_put(pipeline_json['id'], pipeline)
      end
    end

    # TODO: clean up, eliminate the need to keep track of pipelines / apps we've created already
    # TODO: for existing project, apps, pipelines do we update or delete and create, pass a flagg, do a diff??
    def upload
      project_apps_hash = {}

      Dir["#{BUILD_DIR}/*/*/*"].each do|path|
        puts path

        pipeline = IO.read(path)

        project_name = path.split('/')[-3]
        app_name = path.split('/')[-2]


        uploader.create_project({
          "name": "#{project_name}-managed",
          "email": "erratic@supernets.com",
          "config": {
            applications: [],
            "pipelineConfigs": [],
            "clusters": []
          },
        })

        project_apps_hash[project_name] = Set.new unless project_apps_hash[project_name]
        project_apps_hash[project_name].add(app_name)

        # TODO: authoratative eventually flag
        create_application({
          name: "#{app_name}-managed",
          email: "erratic@supernets.com",
          cloudProviders: "kubernetes",
          instancePort: 80,
          dataSources: {
            disabled: [],
            enabled: ['canaryConfigs']
          }
        }, project_name)

        # associate applications w/ projects

        create_pipeline(pipeline)
      end

      puts "apps hash"
      puts project_apps_hash

      project_apps_hash.each do |project_name, apps_set|
        create_project({
          name: "#{project_name}-managed",
          email: 'shipwright@google.com',
          config: {
            applications: apps_set.to_a.map{|app_name| "#{app_name}-managed"},
            pipelineConfigs: [],
            # TODO: add clusters
            clusters: []
          },
        }, true)
      end
    end
  end
end
