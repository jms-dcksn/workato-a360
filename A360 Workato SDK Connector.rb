{
  title: "A360",
  connection: {
    fields: [
      {
        name: "Control_Room_URL",
        optional: false
      },
      {
        name: "username",
        optional: false
      },
      {
        name: "password",
        control_type: 'password',
        optional: false
      }
    ],

    authorization: {
      type: "custom_auth",
      
        acquire: lambda do |connection|
        token_url = "#{connection['Control_Room_URL']}/v1/authentication"
        response = post(token_url). 
                    payload(username: "#{connection['username']}",
                      password: "#{connection['password']}").
            request_format_json
          
        {
          token: response["token"]
        }
        end,
      
      # A360 takes user credentials in an auth request and returns an expiring token
      apply: lambda do |connection|
        headers("X-Authorization": "#{connection['token']}")
      end
    },
    base_uri: lambda do |connection|
      "#{connection['Control_Room_URL']}"
    end
  },
  test: lambda do |connection|
    post('/v1/usermanagement/users/list').
      payload(fields: []).
      request_format_json
  end,
  
  actions: {
    Deploy_Bot: {
      title: "Deploy Bot",
      subtitle: "Deploy a bot from an A360 Control Room",
      description: "Deploy a bot with Bot Deploy API",
      help: "This action can be used to deploy a specific bot to run via a Run As User." \
        " Ensure the Run As User has a default device set or input a Pool ID.",

     
      input_fields: lambda do 
        [
          {
            name: "folderPath",
            label: "Folder Path in Public Repository",
            optional: false,
            control_type: 'select',
            pick_list: 'folder_paths'
          },
          {
            name: 'fileId',
            label: "Bot File ID",
            control_type: 'select',
            pick_list: 'bot_file_id',
            pick_list_params: { folder_id: 'folderPath' },
            type: :integer,
            convert_input: "integer_conversion",
            optional: false
          },
          {
            name: 'botInput',
            label: 'Bot Input (String input to $workatoPayload$ bot variable)',
            type: :string,
            convert_input: 'bot_input_conversion',
            optional: true
          },
          {
            name: "runAsUserIds",
            label: "Run As User",
            control_type: 'select',
            pick_list: 'run_as_users',
            type: :integer,
            convert_input: "integer_conversion",
            optional: false
          },
          {
            name: "poolIds",
            label: "Pool ID",
            type: :integer,
            control_type: 'select',
            pick_list: 'pools',
            convert_input: "integer_conversion",
            optional: false
          },
          {
            name: "callbackInfo",
            label: "Callback URL",
            type: :object,
            properties: [
              {
                name: "url",
                control_type: :url 
              }
            ]
          }
        ]
      end,

      execute: lambda do |connection, _input|
        error("Provide all inputs") if _input.blank?
        post("/v3/automations/deploy").
          payload(fileId: _input['fileId'],
                  botInput: _input['botInput'],
                  runAsUserIds: [_input['runAsUserIds']],
                  poolIds: [_input['poolIds']],
                  callbackInfo: _input['callbackInfo'])
      end,
      output_fields: lambda do |object_definitions|
        [
          { name: "Deployment Id"}
        ]
      end,

      sample_output: lambda do |connection, _input|
        {
          "Deployment Id" => "27fddc7d-d931-4960-ac0f-0b9fea5fd6c4"
        }
      end
    },
    Create_AARI_Request: {
      title: "Create AARI Request",
      subtitle: "Create a new AARI request",
      description: "Creates AARI request via API",
      help: "Add a new request to a process.",
      
      
      input_fields: lambda do |methods|
        [
          {
            name: 'processId',
            label: "Process ID",
            control_type: 'select',
            pick_list: 'aari_processes',
            type: :integer,
            convert_input: "integer_conversion",
            optional: false
           },
          {
            name: 'inputs',
            label: 'Value Inputs for Request',
            control_type: "key_value",
            type: :array,
            of: :object,
            properties: [
              {
                name: 'Element'
              },
              {
                name: 'Value'
              }
            ],
            convert_input: 'key_value_conversion',
            optional: false
          }
        ]
      end,
      
      execute: lambda do |_connection, _input|
        error("Provide all inputs") if _input.blank?
        post("/aari/v2/requests/create", _input)
      end,
      output_fields: lambda do |object_definitions|
        [
          { name: 'id'},
          {name: 'ref'}
        ]
      end,


      sample_output: lambda do |_connection, _input|
        {
          "id": 5327,
          "ref": "0-85"
        }
      end
    }
  },
  
  pick_lists: {
    folder_paths: lambda do |_connection|
      post("/v2/repository/workspaces/public/files/list").
        payload(filter: {
          operator: "eq",
          field: "type",
          value: "application/vnd.aa.directory"
        })&.
        dig('list')&.
        pluck('path', 'id')
    end,
    bot_file_id: lambda do |_connection, folder_id:|
      #folder_id_param = folder_id
      post("v2/repository/folders/" + folder_id + "/list").
        payload(filter: {
          operator: "eq",
          field: "type",
          value: "application/vnd.aa.taskbot"
        })&.
        after_error_response(400) do |code, body, headers|
          error("Error loading pick list: #{body} for folder id: " + folder_id)
        end.
        dig('list')&.
        pluck('name', 'id')
    end,
    run_as_users: lambda do |_connection|
      post("/v1/devices/runasusers/list").
        payload(fields: [])&.
        dig('list')&.
        pluck('username', 'id')
    end,
    pools: lambda do |_connection|
      post("/v2/devices/pools/list").
        payload(fields: []).
        dig('list').
        pluck('name', 'id')
    end,
    aari_processes: lambda do |_connection|
      post("aari/v2/processes/list").
        payload(fields: []).
        dig('list').
        pluck('name', 'id')
    end,
    status: lambda do |_connection|
      [
        ["In Progress", "UPDATE"],
        ["Complete", "COMPLETED"],
        ["Run Failed", "RUN_FAILED"],
        ["Deploy Failed", "DEPLOY_FAILED"]
      ]
    end
  },
  
  methods: {
     key_value_conversion: lambda do |val|
       #iterate over the array object from user input, then 
       if val.is_a?(Array)
        val.inject(:merge)
       else
          {
            val['Element'] => { "string" => val['Value'] }
          }
          end
        end,
    bot_input_conversion: lambda do |val|
      {   
          "workatoPayload" => {
            "type" => "STRING",
            "string" => val
          } 
      }
    end
     },
  
  webhook_keys: lambda do |params, headers, payload|
     "#{payload['result']}"#"partFound"  #payload['result']
  end,
  
  triggers: {
    #This trigger was created specific to a demo, where the bot was configured to send a webhook that matches the below output.
    bot_output: {
      title: 'Bot Run Complete',
      
      subtitle: "Triggers when a bot completes execution.",
      
      description: "New bot output received",
      
      help: "Triggers on a specific bot that is configured to send a webhook with its output/result. " \
        "First, enter an expected bot output in the input field. If the payload from the bot includes "\
        "that output, the trigger will be activated. The appropriate payload should be configured in the A360 Bot sending the webhook.",
      
      input_fields: lambda do 
        [
         {
           name: 'bot_result',
           optional: false
         } 
        ]
      end,
      
      webhook_key: lambda do |connection, input|
        "#{input['bot_result']}"    #input['bot_result']
      end,
      
      webhook_notification: ->(_connection, payload) { payload },
      
      dedup: ->(output) { "#{output['id']}@#{output['createdAt']}" },
      
#       dedup: lambda do |record|
#         "#{record['id']}@#{record['createdAt']}" #string here of id and timestamp
#       end,
      output_fields: lambda do |connection|
        [
          {
            name: 'orderId'
          },
          {
            name: 'productId'
          },
          {
            name: 'orderItem'
          }
        ]
      end,
      sample_output: lambda do |connection, input|
        {
          data: "id: orderId: etc."
        }
      end
    },
    
    automation_status: {
      title: 'Automation Status',
      
      subtitle: "Triggers on a user-defined status of an automation in A360",
      
      description: "Select bot to monitor and status to define trigger activation.",
      
      help: "Trigger will be activated when the selected automation is deployed and matches the defined status.",
      
      input_fields: lambda do 
        [
          {
            name: "folderPath",
            label: "Folder Path in Public Repository",
            optional: false,
            control_type: 'select',
            pick_list: 'folder_paths'
          },
          {
            name: 'fileId',
            label: "Bot File ID",
            control_type: 'select',
            pick_list: 'bot_file_id',
            pick_list_params: { folder_id: 'folderPath' },
            type: :integer,
            optional: false
          },
          {
            name: 'status',
            control_type: 'select',
            pick_list: 'status',
            optional: false
          },
          {
            name: 'since',
            label: 'When first started, this recipe should pick up events from',
            type: 'timestamp',
            optional: true,
            sticky: true,
            hint: 'When you start recipe for the first time, it picks up ' \
            'trigger events from this specified date and time. Defaults to ' \
            'the current time.'
          }
        ]
      end,
      
      poll: lambda do |connection, input, closure|
        
        closure = {} unless closure.present?
        
        page_size = 200 #need to add pagination
        offset = 0 unless offset.present?
        
        updated_since = (closure['cursor'] || input['since'] || Time.now ).to_time.utc.iso8601 #need to valide time format
        
        statuses = post('/v2/activity/list').
          payload(sort: [{
                      field: 'startDateTime',
                      direction: 'asc'
                  }],
                  filter: {
                    operator: 'and',
                    operands: [
                      {
                        operator: 'eq',
                        field: 'fileId',
                        value: input['fileId']
                      },
                      {
                        operator: 'gt',
                        field: 'startDateTime',
                        value: updated_since
                      },
                      {
                        operator: 'eq',
                        field: 'status',
                        value: input['status']
                      }
                    ]
                  },
            page: {
              length: page_size,
              offset: offset
            }
                )
        
       
        trigger_list = statuses.dig('list')
        page_info = statuses.dig('page')
        
        if page_info['totalFilter'] > (page_info['offset'] + page_size)
          offset = offset + page_size
          poll_more = true
        else
          offset = 0
          poll_more = false
        end
        
        #Can poll more could be set by checking if offset greater then sum of total and page
        #Need to include page size in API filter, and conditionally set offset to implement pagination
        
        closure['cursor'] = trigger_list.last['startDateTime'] unless trigger_list.blank?
        {
          events: trigger_list,
          next_poll: closure,
          can_poll_more: poll_more 
        }
      end,
      
      dedup: ->(record) { "#{record['id']}@#{record['startDateTime']}" },
      
      output_fields: lambda do 
        [
          {
            name: 'status'
          },
          {
            name: 'automationName'  
          },
          {
            name: 'fileName'
          },
          {
            name: 'message'
          },
          {
            name: 'deploymentId'
          },
          {
            name: 'deviceName'
          },
          {
            name: 'userName'
          },
          {
            name: 'currentLine'
          },
          {
            name: 'command'
          }
        ]
      end
    }
  }
}