# encoding: UTF-8
require 'bundler'
require 'json'

Bundler.require                    # defaults to all groups

url = 'https://api.github.com/graphql'
token = File.read('graphql.token').strip

payload = {
  "query": "query {
    organization(login: \"hashrocket\") {
      members(first:50) {
        edges {
          node {
            ... on User {
              login
              name
              repositories(first:100) {
                pageInfo {
                  endCursor
                  hasNextPage
                }
                edges {
                  node {
                    name
                    object(expression: \"master:.hrconcept\") {
                      ... on Blob {
                        text
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }"
}

response = RestClient.post url, payload.to_json, {'Authorization' => "bearer #{token}"}

puts "Successful initial github query with code: #{response.code}"

graphql_response_json = JSON.parse(response.body)

member_edges = graphql_response_json["data"]["organization"]["members"]["edges"]

next_queries = []
concepts = []

member_edges.each do |member_edge|
  login = member_edge["node"]["login"]
  end_cursor = member_edge["node"]["repositories"]["pageInfo"]["endCursor"]
  has_next_page = member_edge["node"]["repositories"]["pageInfo"]["hasNextPage"]

  if has_next_page
    next_queries << [login, end_cursor]
  end

  repo_edges = member_edge["node"]["repositories"]["edges"]

  repo_edges.each do |repo_edge|
    repo_name = repo_edge["node"]["name"]
    repo_concept_config = repo_edge["node"]["object"]

    if repo_concept_config != nil
      concepts << {
        login: login,
        repo_name: repo_name,
        concept_config: repo_concept_config
      }
    end
  end
end

next_queries.each do |(login, end_cursor)|
  payload = {
    "query": "query {
      user(login: \"#{login}\") {
        repositories(first: 100, after: \"#{end_cursor}\") {
          pageInfo {
            hasNextPage
          }
          edges {
            node {
              name
              object(expression: \"master:.hrconcept\") {
                ... on Blob {
                  text
                }
              }
            }
          }
        }
      }
    }"
  }

  response = RestClient.post url, payload.to_json, {'Authorization' => "bearer #{token}"}

  puts "Auxiallary request for #{login} has responded with code: #{response.code}"

  graphql_response_json = JSON.parse(response.body)
  repo_edges = graphql_response_json["data"]["user"]["repositories"]["edges"]

  repo_edges.each do |repo_edge|
    repo_name = repo_edge["node"]["name"]
    repo_concept_config = repo_edge["node"]["object"]

    if repo_concept_config != nil
      concepts << {
        login: login,
        repo_name: repo_name,
        concept_config: repo_concept_config
      }
    end
  end
end

puts "We found #{concepts.count} instances of a .hrconcept"

require 'yaml'
concepts.each do |concept|

  concept_yaml = YAML.load(concept[:concept_config]['text'])

  banner_sub_filter = if concept_yaml['banner']
                        "sub_filter <body> '<body><header style="background-color: #414042; height: 2rem; padding: 0.4rem; color: white;"><img src="https://d15zqjc70bk603.cloudfront.net/assets/brand/hr_logo_h_light-4cb402f22041c39699a752bd21aaa38ebd860b343ae20a5fe97342c8ec53f156.svg"></img></header>';"


                      end
  concept[:concept_url] = "#{concept_yaml['name']}.hrcpt.online";

  nginx = <<~NGINX
  server {
    listen 80;

    server_name #{concept[:concept_url]};

    location / {
      proxy_set_header Accept-Encoding "";
      proxy_pass #{concept_yaml['url']};
      proxy_redirect off;
      proxy_read_timeout 5m;
      proxy_set_header Host $http_host;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-Proto http;
    }

    sub_filter '</head>' '<script>analytics</script></head>';
    #{banner_sub_filter}
  }
  NGINX

  require 'fileutils'
  FileUtils.mkdir_p('nginx')
  File.write("./nginx/#{concept_yaml['name']}", nginx)
end

require 'erb'

File.write("/var/www/concepts.com/index.html", ERB.new(DATA.read).result(binding))

__END__

<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <meta name="theme-color" content="#000000">
    <link rel="shortcut icon" href="https://hashrocket.com/favicon.ico">
    <title>Concepts - Hashrocket</title>
    <styles>
      header {
        background-color: #414042;
        height: 2rem;
        padding: 0.4rem;
        color: white;
      }

      body {
        background-color: white;
        font: Helvetica, sans-serif;
      }

      ul {
        display: flex;
        flex-direction: row;
        flex-wrap: wrap;
        justify-content: space-between;
        min-width: 42rem;
        max-width: 60rem;
        height: 100%;
      }

      li {
        display: flex;
        flex-direction: column;
        background-color: #c8c8c8;
        min-width: 16rem;
        min-height: 8rem;
        margin: 2rem;
      }

      li h2 {
        color: #af1e23;
      }

      li div {
        min-height: 1.6rem;
      }

      a:link, a:active, a:visited, a:hover, a:focus
      {
        decoration: none;
        color: #414042;
      }

    </styles>
  </head>
  <body>
    <header>
      <img src="https://d15zqjc70bk603.cloudfront.net/assets/brand/hr_logo_h_light-4cb402f22041c39699a752bd21aaa38ebd860b343ae20a5fe97342c8ec53f156.svg" class="App-logo" alt="logo">
    </header>
    <section>
      <h1>General</h1>
      <ul>
        <% concepts.each do |concept| %>
        <% concept_yaml = YAML.load(concept[:concept_config]['text']) %>
          <li>
            <div class='title'>
              <a href="http://<%= concept[:concept_url] %>">
                <h2><%= concept_yaml['name'] %></h2>
              </a>
            <div>
            <div class='description'>
              <%= concept_yaml['description'] %>
            </div>
            <div class='repo'>
              <a href="<%= "https://github.com/#{concept[:login]}/#{concept[:repo]}" %>">
                github
              </a>
            </div>
          </li>
        <% end %>
      </ul>
    </section>
  </body>
</html>
