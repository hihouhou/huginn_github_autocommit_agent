module Agents
  class GithubAutocommitAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule 'every_1h'

    description do
      <<-MD
      The Github autocommit agent updates content for repositories and creates an event if wanted.

      `repository` is the name of the repository.

      `version` is the version wanted.

      `commit_message` is the message in the commit.

      `committer_name` is the name of the committer.

      `committer_email` is the email of the committer.

      `token` is needed for authentication

      `rules` is needed to know information about the target repository.

      `emit_events` is for creating an event.

      `debug` to add verbosity.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

          {
              "content": {
                "name": "Dockerfile",
                "path": "Dockerfile",
                "sha": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
                "size": 541,
                "url": "https://api.github.com/repos/hihouhou/docker-test/contents/Dockerfile?ref=master",
                "html_url": "https://github.com/hihouhou/docker-test/blob/master/Dockerfile",
                "git_url": "https://api.github.com/repos/hihouhou/docker-test/git/blobs/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
                "download_url": "https://raw.githubusercontent.com/hihouhou/docker-test/master/Dockerfile",
                "type": "file",
                "_links": {
                  "self": "https://api.github.com/repos/hihouhou/docker-test/contents/Dockerfile?ref=master",
                  "git": "https://api.github.com/repos/hihouhou/docker-test/git/blobs/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
                  "html": "https://github.com/hihouhou/docker-test/blob/master/Dockerfile"
                }
              },
              "commit": {
                "sha": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
                "node_id": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
                "url": "https://api.github.com/repos/hihouhou/docker-test/git/commits/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
                "html_url": "https://github.com/hihouhou/docker-test/commit/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
                "author": {
                  "name": "XXXXXXXX",
                  "email": "XXXXXXXXXXXXXXXXXXXXX",
                  "date": "2023-10-12T23:42:46Z"
                },
                "committer": {
                  "name": "XXXXXXXX",
                  "email": "XXXXXXXXXXXXXXXXXXXXX",
                  "date": "2023-10-12T23:42:46Z"
                },
                "tree": {
                  "sha": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
                  "url": "https://api.github.com/repos/hihouhou/docker-test/git/trees/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
                },
                "message": "my commit message",
                "parents": [
                  {
                    "sha": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
                    "url": "https://api.github.com/repos/hihouhou/docker-test/git/commits/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
                    "html_url": "https://github.com/hihouhou/docker-test/commit/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
                  }
                ],
                "verification": {
                  "verified": false,
                  "reason": "unsigned",
                  "signature": null,
                  "payload": null
                }
              }
          }
    MD

    def default_options
      {
        'repository' => '',
        'version' => '',
        'commit_message' => '',
        'committer_name' => '',
        'committer_email' => '',
        'emit_events' => 'true',
        'expected_receive_period_in_days' => '2',
        'token' => '',
        'rules' => '[{name: "", owner: "", my_repository: "", pattern: "", file: "" }'
      }
    end

    form_configurable :repository, type: :string
    form_configurable :version, type: :string
    form_configurable :commit_message, type: :string
    form_configurable :committer_name, type: :string
    form_configurable :committer_email, type: :string
    form_configurable :token, type: :string
    form_configurable :rules, type: :string
    form_configurable :emit_events, type: :boolean
    form_configurable :debug, type: :boolean
    form_configurable :expected_receive_period_in_days, type: :string

    def validate_options
      unless options['repository'].present?
        errors.add(:base, "repository is a required field")
      end

      unless options['version'].present?
        errors.add(:base, "version is a required field")
      end

      unless options['commit_message'].present?
        errors.add(:base, "commit_message is a required field")
      end

      unless options['committer_name'].present?
        errors.add(:base, "committer_name is a required field")
      end

      unless options['committer_email'].present?
        errors.add(:base, "committer_email is a required field")
      end


      unless options['token'].present?
        errors.add(:base, "token is a required field")
      end
#
#      if options[:type] == :array && (options[:values].blank? || !options[:values].is_a?(Array))
#        raise ArgumentError.new('When using :array as :type you need to provide the :values as an Array')
#      end

      if options.has_key?('add_release_details') && boolify(options['add_release_details']).nil?
        errors.add(:base, "if provided, add_release_details must be true or false")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      if options.has_key?('emit_events') && boolify(options['emit_events']).nil?
        errors.add(:base, "if provided, emit_events must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          log event
          commit
        end
      end
    end

    def check
      commit
    end

    private

    def log_curl_output(code,body)

      log "request status : #{code}"

      if interpolated['debug'] == 'true'
        log "body"
        log body
      end

    end

    def update_content(owner,repository,filepath,content,sha)
      encoded_content = Base64.strict_encode64(content)

      uri = URI.parse("https://api.github.com/repos/#{owner}/#{repository}/contents/#{filepath}")
      request = Net::HTTP::Put.new(uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/vnd.github+json"
      request["Authorization"] = "token #{interpolated['token']}"
      request["X-Github-Api-Version"] = "2022-11-28"
      request.body = JSON.dump({
        "message" => "#{interpolated['commit_message']}",
        "committer" => {
          "name" => "#{interpolated['committer_name']}",
          "email" => "#{interpolated['committer_email']}"
        },
        "content" => "#{encoded_content}",
        "sha" => "#{sha}"
      })
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }
      
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log_curl_output(response.code,response.body)

      if interpolated['emit_events'] == 'true'
        create_event payload: response.body
      end    
    end    
    
    def commit
      to_apply = {}
      JSON.parse(interpolated['rules']).each do | rule |
        if interpolated['repository'] == rule['name']
          to_apply = rule
          if interpolated['debug'] == 'true'
            log "found"
          end
        else
          if interpolated['debug'] == 'true'
            log "not found"
          end
        end
      end

      uri = URI.parse("https://api.github.com/repos/#{to_apply['owner']}/#{to_apply['my_repository']}/contents/#{to_apply['file']}")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "token #{interpolated['token']}"
#      request["Authorization"] = interpolated['token']
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }
      
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log_curl_output(response.code,response.body)
      
      data = JSON.parse(response.body)
      file_content_base64 = data['content']
      sha = data['sha']
      
      file_content = Base64.decode64(file_content_base64)
      current_version = file_content.match(/^ENV #{to_apply['pattern']} (.*)/)
      if current_version && current_version[1] >= interpolated['version']
        log "The current version is already greater than or equal to the given version. No replacement necessary."
      else
        file_content.gsub!(/^ENV #{to_apply['pattern']}.*/, "ENV #{to_apply['pattern']} #{interpolated['version']}")
        update_content(to_apply['owner'],to_apply['my_repository'],to_apply['file'],file_content,sha)
#        log file_content
      end
    end    
  end
end
