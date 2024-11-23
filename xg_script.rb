require 'nokogiri'
require 'httparty'
require 'watir'
require 'selenium-webdriver'
require 'webdrivers'
require 'pry'
require 'pry-nav'
require 'capybara'
require 'active_support'
require 'active_support/time'
require 'distribution'
require 'mechanize'
require 'net/http'
require 'uri'
require 'json'
require 'csv'


# THRESHOLDS
THRESHOLDS = {
  UNDER_OVER_HALF_THRESHOLD: { index: [-1], value: 80 },
  SINGLE_THRESHOLD: { index: [2,4], value: 60 },
  DRAW_THRESHOLD: { index: [3], value: 35 },
  DOUBLE_THRESHOLD: { index: [5, 6, 7], value: 75 },
  UNDER_OVER_THRESHOLD: { index: [8, 9, 10, 11, 12, 13], value: 80 },
  GG_THRESHOLD: { index: [14], value: 80 },
  CORNER_THRESHOLD: { index: [-1], value: 80 },
  CARDS_THRESHOLD: { index: [16], value: 80 },
  PENALTY_THRESHOLD: { index: [-1], value: 80 },
  RED_CARD_THRESHOLD: { index: [-1], value: 80 },
  SCORER_THRESHOLD: { index: [-1], value: 60 }
}

NAMES_MAP = {
  'Wolves' => 'Wolverhampton_Wanderers',
  'Newcastle' => 'Newcastle_United',
  'Betis' => 'Real_Betis',
  'Celta' => 'Celta_Vigo',
  'Heidenheim' => 'FC_Heidenheim',
  'RB Leipzig' => 'RasenBallsport_Leipzig',
  'Paris Saint-Germain' => 'Paris_Saint_Germain',
  'FC Koln' => 'FC_Cologne',
  'Deportivo Alaves' => 'Alaves'
}

NUMBER_OF_SIMULATIONS = 10000

AVAILABLE_LEAGUES = ['LaLiga', 'Serie A', 'Bundesliga', 'Ligue 1',
                     'Champions League', 'Europa League',
                     'Championship', 'Premiership', 'Liga Portugal',
                     'Premier League', 'Super Lig', 'Eredivisie',
                     'UEFA Nations League A', 'UEFA Nations League B',
                     'UEFA Nations League C', 'UEFA Nations League D',
                     'League One', 'League Two' ]

def games(url)
  @br = Watir::Browser.new
  @br.goto(url)

  a = JSON.parse(@br.elements.first.text)['tournaments'].
    #select { |x| AVAILABLE_LEAGUES.include?(x['tournamentName'])}.
    map { |x| x['matches'].map do |g|
      next if DateTime.now > DateTime.parse(g['startTime']).utc

      {
        id: g['id'],
        home: g['homeTeamName'],
        home_id: g['homeTeamId'],
        away: g['awayTeamName'],
        away_id: g['awayTeamId'],
        url: "https://www.whoscored.com/Matches/#{g['id']}/Preview/",
        tournament_id: x['tournamentId'],
        tournament_name: x['tournamentName']
      }
    end
  }.flatten.compact
  a
ensure
  @br.quit
end

def starting_eleven(url)
  @br = Watir::Browser.new :chrome, headless: :true
  @br.driver.manage.timeouts.page_load = 180 # Set a 3-minute timeout

  @br.goto(url)
  @br.elements(class: 'player-name player-link cnt-oflow rc').wait_until(timeout: 60) do |p|
    p.all?{ |x| !x.inner_html.empty? }
  end

  a = {
    home: @br.elements(class: 'player-name player-link cnt-oflow rc').map(&:inner_html).take(11),
    away: @br.elements(class: 'player-name player-link cnt-oflow rc').map(&:inner_html).reverse.take(11)
  }
  a
ensure
  @br.quit
end

def goal_and_assist(goal, assist)
  (goal + assist - (goal * assist)) * 100
end

def xgs_new(home_team, away_team, home_id, away_id, starting_eleven, competition_id)
  @br = Watir::Browser.new
  @br.driver.manage.timeouts.page_load = 180 # Set a 3-minute timeout

  home_url = "https://www.whoscored.com/StatisticsFeed/1/GetPlayerStatistics?category=xg-stats&subcategory=summary&statsAccumulationType=0&tournamentOptions=#{competition_id}&isCurrent=true&playerId=&teamIds=#{home_id}&sortBy=xg&sortAscending=false&field=Overall&isMinApp=false&page=&includeZeroValues=true&numberOfPlayersToPick=&incPens=true"
  away_url = "https://www.whoscored.com/StatisticsFeed/1/GetPlayerStatistics?category=xg-stats&subcategory=summary&statsAccumulationType=0&tournamentOptions=#{competition_id}&isCurrent=true&playerId=&teamIds=#{away_id}&sortBy=xg&sortAscending=false&field=Overall&isMinApp=false&page=&includeZeroValues=true&numberOfPlayersToPick=&incPens=true"
  home_team_url = "https://www.whoscored.com/Teams/#{home_id}/Show"
  away_team_url = "https://www.whoscored.com/Teams/#{away_id}/Show"
  @br.goto(home_url)
  xgs_warning = false
  home_xgs = starting_eleven[:home].each_with_object({}) do |p, hsh|
    hsh[p] = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p) && x['tournamentId'] == competition_id}&.first.try(:[], 'xGPerNinety') || 0
  end

  xgs_warning = true if home_xgs.count{ |_,v| v.to_i == 0} < 9

  home_cards_url = "https://www.whoscored.com/StatisticsFeed/1/GetPlayerStatistics?category=summary&subcategory=all&statsAccumulationType=0&isCurrent=true&playerId=&teamIds=#{home_id}&matchId=&stageId=&tournamentOptions=#{competition_id}&sortBy=Rating&sortAscending=&age=&ageComparisonType=&appearances=&appearancesComparisonType=&field=Overall&nationality=&positionOptions=&timeOfTheGameEnd=&timeOfTheGameStart=&isMinApp=false&page=&includeZeroValues=true&numberOfPlayersToPick=&incPens="
  @br.goto(home_cards_url)

  home_cards = starting_eleven[:home].each_with_object({}) do |p, hsh|
    yellow = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p) && x['tournamentId'] == competition_id}&.first.try(:[], 'yellowCard') || 0
    red = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p) && x['tournamentId'] == competition_id}&.first.try(:[], 'redCard') || 0
    apps = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p) && x['tournamentId'] == competition_id}&.first.try(:[], 'apps') || 0
    hsh[p] = apps.zero? ? 0 : ((yellow + red) / apps.to_f)
  end

  @br.goto(away_url)
  away_xgs = starting_eleven[:away].each_with_object({}) do |p, hsh|
    hsh[p] = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p)}&.first.try(:[], 'xGPerNinety') || 0
  end

  xgs_warning = true if away_xgs.count{ |_,v| v.to_i == 0} < 9

  away_cards_url = "https://www.whoscored.com/StatisticsFeed/1/GetPlayerStatistics?category=summary&subcategory=all&statsAccumulationType=0&isCurrent=true&playerId=&teamIds=#{away_id}&matchId=&stageId=&tournamentOptions=#{competition_id}&sortBy=Rating&sortAscending=&age=&ageComparisonType=&appearances=&appearancesComparisonType=&field=Overall&nationality=&positionOptions=&timeOfTheGameEnd=&timeOfTheGameStart=&isMinApp=false&page=&includeZeroValues=true&numberOfPlayersToPick=&incPens="
  @br.goto(away_cards_url)

  away_cards = starting_eleven[:away].each_with_object({}) do |p, hsh|
    yellow = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p) && x['tournamentId'] == competition_id}&.first.try(:[], 'yellowCard') || 0
    red = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p) && x['tournamentId'] == competition_id}&.first.try(:[], 'redCard') || 0
    apps = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p) && x['tournamentId'] == competition_id}&.first.try(:[], 'apps') || 0
    hsh[p] = apps.zero? ? 0 : ((yellow + red) / apps.to_f)
  end
  sleep(1)
  begin
    binding.pry
    url = "https://www.whoscored.com/StatisticsFeed/1/GetTeamStatistics"
    response = HTTParty.get(url, query: query_params, headers: headers)
    binding.pry

    @br.goto(home_team_url)
    if @br.button(text: "AGREE").exists?
      @br.button(text: "AGREE").click
    elsif @br.a(text: "AGREE").exists?
      @br.a(text: "AGREE").click
    end
    sleep(1)
    if @br.button(class: 'webpush-swal2-close').exists?
      @br.button(class: 'webpush-swal2-close').click
    end

    sleep(1)
    @br.a(text: "xG").wait_until(&:present?)
    @br.a(text: "xG").click
    sleep(1)
    @br.a(text: "Against").wait_until(&:present?)
    @br.a(text: "Against").click
    sleep(1)
    @br.wait_until(timeout: 60) { @br.div(id: 'statistics-team-table-xg').exists? }
    @br.wait_until(timeout: 60) { @br.div(id: 'statistics-team-table-xg').trs.length > 1 }

    sleep(1)
    home_team_xga = nil
    @br.div(id: 'statistics-team-table-xg').divs.first.tables.first.tbodys.first.trs.each do |tr|
      ctournament_id = tr.first.a.href.split('Tournaments/').last.split('/').first.to_i
      next unless ctournament_id == competition_id

      home_team_xga = tr.tds[2].text.to_f / tr.tds[1].text.to_f
    end
    sleep(1)
    @br.goto(away_team_url)
    @br.a(text: "xG").click
    @br.a(text: "Against").click
    @br.wait_until(timeout: 60) { @br.div(id: 'statistics-team-table-xg').exists? }
    @br.wait_until(timeout: 60) { @br.div(id: 'statistics-team-table-xg').trs.length > 1 }

    sleep(1)
    away_team_xga = nil

    @br.div(id: 'statistics-team-table-xg').divs.first.tables.first.tbodys.first.trs.each do |tr|
      ctournament_id = tr.first.a.href.split('Tournaments/').last.split('/').first.to_i
      next unless ctournament_id == competition_id

      away_team_xga = tr.tds[2].text.to_f / tr.tds[1].text.to_f
    end
  rescue Selenium::WebDriver::Error::StaleElementReferenceError
    puts "Encountered a stale element reference, retrying..."
    retry
  rescue Net::ReadTimeout => e
    puts "Encountered a timeout, retrying..."
    retry
  rescue Watir::Wait::TimeoutError => e
    puts "Encountered a timeout, retrying..."
    retry
  end

  stats = {
    home_xgs: home_xgs,
    away_xgs: away_xgs,
    xgs_warning: xgs_warning,
    home_xga: home_team_xga,
    away_xga: away_team_xga,
    home_cards: home_cards,
    away_cards: home_cards
  }
  stats
rescue => e
 #binding.pry
ensure
  @br.quit
  return stats
end

def write_to_index_file(res)
  open("index.txt", 'a') { |f|
  f.puts res
}
end

def query_params
  {
    category: 'summaryteam',
    subcategory: 'all',
    statsAccumulationType: '0',
    field: 'Overall',
    tournamentOptions: '',
    timeOfTheGameStart: '',
    timeOfTheGameEnd: '',
    teamIds: '23777',
    stageId: '',
    sortBy: 'Rating',
    sortAscending: '',
    page: '',
    numberOfTeamsToPick: '',
    isCurrent: 'true',
    formation: '',
    incPens: '',
    against: ''
  }
end

def headers
  {
    'accept' => 'application/json, text/javascript, */*; q=0.01',
    'accept-language' => 'en-GB,en-US;q=0.9,en;q=0.8',
    'cache-control' => 'no-cache',
    'cookie' => cookies,
    'model-last-mode' => 'pOW14CDwuF1urhs/hDXK+y+i7dfVG+6o9sdttM2zMhk=',
    'pragma' => 'no-cache',
    'priority' => 'u=1, i',
    'referer' => 'https://www.whoscored.com/Teams/23777/Show',
    'sec-ch-ua' => '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"',
    'sec-ch-ua-mobile' => '?0',
    'sec-ch-ua-platform' => '"macOS"',
    'sec-fetch-dest' => 'empty',
    'sec-fetch-mode' => 'cors',
    'sec-fetch-site' => 'same-origin',
    'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'x-requested-with' => 'XMLHttpRequest'
  }
end

def cookies
  #'_oid=8a45c561-b765-4a40-a97f-0aca4f7081de; _au_1d=AU1D-0100-001709297287-0ZP1A37R-NJZC; usprivacy=1Y--; _fbp=fb.1.1724099143502.430990829828205857; ct=GR; pbjs_pubcommonID=8b92bf3c-56b3-443c-9eec-b996ac061454; cookie=34a37bba-d570-43a4-b126-bfa481502d69; _cc_id=be72b03c10a1b7da9bb44cbcfde069d5; ccuid=14e3636b-b17c-4f36-a077-a581e6ccd470; _xpid=4697159903; _xpkey=PY33MWoW_zh4cKM9V_u2gQKRv7R1HFOD; uuid=6383E33A-6BFF-46F0-BD23-A2D853FE9878; _ga_58Q95H24XC=GS1.1.1727599333.1.0.1727600811.60.0.0; pbjs_unifiedID=%7B%22TDID_LOOKUP%22%3A%22FALSE%22%2C%22TDID_CREATED_AT%22%3A%222024-11-11T11%3A26%3A03%22%7D; euconsent-v2=CQIVlIAQIVlIAAKA1AENBQFsAP_gAEPgAAwIKlNX_G__bWlr8X73aftkeY1P9_h77sQxBhfJE-4FzLvW_JwXx2ExNA36tqIKmRIAu3TBIQNlGJDURVCgaogVryDMaEiUoTNKJ6BkiFMRM2dYCFxvm4tj-QCY5vr991dx2B-t7dr83dzyy4xHn3a5_2S0WJCdA5-tDfv9bROb-9IOd_x8v4v4_F_pE2_eT1l_tWvp7D9-cts7_XW89_fff_9Pn_-uB_-_3_vfBTUAkw0KiAMsiQkINAwggQAqCsICKBAAAACQNEBACYMCnYGAC6wkQAgBQADBACAAEGQAIAABIAEIgAgAKBAABAIFAAAAAAIBAAwMAAYALAQCAAEB0CFMCCAQLABIzIiFMCEIBIICWyoQSAIEFcIQizwAIBETBQAAAkAFIAAgLBYHEkgJWJBAFxBtAAAQAIBBAAUIpOzAEEAZstReKBtGVpAWD5gKOAAABAAA.f_gAAAAAAAAA; addtl_consent=1~43.3.9.6.9.13.6.4.15.9.5.2.11.8.1.3.2.10.33.4.15.17.2.9.20.7.20.5.20.7.2.2.1.4.40.4.14.9.3.10.8.9.6.6.9.41.5.3.1.27.1.17.10.9.1.8.6.2.8.3.4.146.65.1.17.1.18.25.35.5.18.9.7.41.2.4.18.24.4.9.6.5.2.14.25.3.2.2.8.28.8.6.3.10.4.20.2.17.10.11.1.3.22.16.2.6.8.6.11.6.5.33.11.8.11.28.12.1.5.2.17.9.6.40.17.4.9.15.8.7.3.12.7.2.4.1.7.12.13.22.13.2.6.8.10.1.4.15.2.4.9.4.5.4.7.13.5.15.17.4.14.10.15.2.5.6.2.2.1.2.14.7.4.8.2.9.10.18.12.13.2.18.1.1.3.1.1.9.7.2.16.5.19.8.4.8.5.4.8.4.4.2.14.2.13.4.2.6.9.6.3.2.2.3.7.3.6.10.11.9.19.8.3.3.1.2.3.9.19.26.3.10.13.4.3.4.6.3.3.3.4.1.1.6.11.4.1.11.6.1.10.13.3.2.2.4.3.2.2.7.15.7.14.4.3.4.5.4.3.2.2.5.5.3.9.7.9.1.5.3.7.10.11.1.3.1.1.2.1.3.2.6.1.12.8.1.3.1.1.2.2.7.7.1.4.3.6.1.2.1.4.1.1.4.1.1.2.1.8.1.7.4.3.3.3.5.3.15.1.15.10.28.1.2.2.12.3.4.1.6.3.4.7.1.3.1.4.1.5.3.1.3.4.1.5.2.3.1.2.2.6.2.1.2.2.2.4.1.1.1'
  browser = Watir::Browser.new
  browser.driver.manage.timeouts.page_load = 300 # Increase to 5 minutes

  binding.pry
  browser.goto('https://www.whoscored.com/Teams/23777/Show')

  if browser.button(text: 'AGREE').present?
    browser.button(text: 'AGREE').click
  elsif browser.a(text: 'AGREE').present?
    browser.a(text: 'AGREE').click
  end

  # Close any other pop-ups if necessary
  if browser.button(class: 'webpush-swal2-close').exists?
    browser.button(class: 'webpush-swal2-close').click
  end

  # Wait for the page to fully load
  browser.div(class: 'team-header').wait_until(&:present?)

  # Capture cookies
  cookie_string = browser.cookies.to_a.map { |c| "#{c[:name]}=#{c[:value]}" }.join('; ')
  browser.close

  cookie_string
end

def export_to_csv(proposals)
  headers = ['Home', 'Away','1', 'X', '2', '1X', 'X2', '12', 'O15', 'U15', 'O25', 'U25', 'O35', 'U35', 'GG', 'Missing XGS', 'Both Cards']
  CSV.open("bet_proposals.csv", "a", :write_headers=> (!File.exist?("bet_proposals.csv") || !CSV.read("bet_proposals.csv", headers: true).headers == headers),
                                     :headers => headers, col_sep: ';') do |csv|
    proposals.each do |game|
      #puts "#{game[:home_team]}-#{game[:away_team]}: #{game.except(:home_team, :away_team, :missing_xgs).values.select{|k, v| v.to_i > 80}.join(',')}"
      puts game if game.except(:home_team, :away_team, :missing_xgs).values.any?{|v| v.to_i > 80} && !game[:missing_xgs]
      csv << [game[:home_team], game[:away_team], game[:home], game[:draw], game[:away], game[:home] + game[:draw], game[:draw] + game[:away], game[:home] + game[:away], game[:over15], game[:under15], game[:over25], game[:under25], game[:over35], game[:under35], game[:gg], game[:missing_xgs], game[:both_cards]]
    end
  end;0
end

def read_index_file
  File.readlines('index.txt', chomp: true).map(&:to_i)
end

def import_from_csv
  CSV.read("bet_proposals.csv", headers: true, col_sep: ';').map(&:to_h)
end

def print_proposals
  games = import_from_csv
  proposals = Hash.new {|hsh, key| hsh[key] = [] }
  games.each do |g|
    next if g['Missing XGS'] == 'true'

    g.each_with_index do |(k,v), i|
      next if ['Missing XGS', 'Home', 'Away'].include?(k)

      proposals["#{g['Home']}-#{g['Away']}"] << "#{k}(#{v})" if v.to_f > THRESHOLDS.select{|_,v| v[:index].include?(i)}.values.first[:value]
      proposals
    end
  end
  proposals.each{ |k, v| pp "#{k} -> #{v.join(',')}"}
end

def simulate_match(home_team, away_team, stats)
  res = {
    home_team: home_team,
    away_team: away_team,
    missing_xgs: stats[:xgs_warning],
    home: 0,
    draw: 0,
    away: 0,
    under15: 0,
    over15: 0,
    under25: 0,
    over25: 0,
    under35: 0,
    over35: 0,
    gg: 0,
    two_three: 0,
    both_cards: 0,
    #home_scorers: {},
    #away_scorers: {}
  }

  home_scorers = []
  away_scorers = []
  home_assists = []
  away_assists = []
  scores = []

  puts "Simulating games..."

  NUMBER_OF_SIMULATIONS.times do
    home_xg_stats = stats[:home_xgs].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    away_xg_stats = stats[:away_xgs].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    #home_assist_stats = stats[:home_xas].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    #away_assist_stats = stats[:away_xas].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    home_yellow_cards = stats[:home_cards].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    away_yellow_cards = stats[:away_cards].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}

    home_xga = Distribution::Poisson.rng(stats[:home_xga])
    away_xga = Distribution::Poisson.rng(stats[:away_xga])
    home = ([home_xg_stats.sum{ |_, v| v }, away_xga].min + ((home_xg_stats.sum{ |_, v| v } - away_xga).abs / 3.333)).round
    away = ([away_xg_stats.sum{ |_, v| v }, home_xga].min + ((away_xg_stats.sum{ |_, v| v } - home_xga).abs / 3.333)).round

    home_scorers << home_xg_stats.each_with_object([]) { |k, arr| arr << [k[0]] * k[1] }.flatten.sample(home)
    away_scorers << away_xg_stats.each_with_object([]) { |k, arr| arr << [k[0]] * k[1] }.flatten.sample(away)
    #home_assists << home_assist_stats.keys
    #away_assists << away_assist_stats.keys

    scores << "#{home}-#{away}"

    if home == away
      res[:draw] += 1
    elsif home > away
      res[:home] += 1
    else
      res[:away] += 1
    end

    if home + away > 1.5
      res[:over15] += 1
    else
      res[:under15] += 1
    end

    if home + away > 2.5
      res[:over25] += 1
    else
      res[:under25] += 1
    end

    if home + away > 3.5
      res[:over35] += 1
    else
      res[:under35] += 1
    end

    if home.positive? && away.positive?
      res[:gg] += 1
    end

    if [2, 3].include?(home + away)
      res[:two_three] += 1
    end

    home_yellow = home_yellow_cards.sum{ |_, v| v }
    away_yellow = away_yellow_cards.sum{ |_, v| v }
    if home_yellow > 0 && away_yellow > 0
      res[:both_cards] += 1
    end
  end

  #res[:home_scorers] = home_scorers.flatten.tally.transform_values{|x| x / (NUMBER_OF_SIMULATIONS / 100).to_f}
  #res[:away_scorers] = away_scorers.flatten.tally.transform_values{|x| x / (NUMBER_OF_SIMULATIONS / 100).to_f}

  return res.merge(res.except(:home_team, :away_team, :missing_xgs, :home_scorers, :away_scorers).transform_values{ |v| v / (NUMBER_OF_SIMULATIONS / 100.0) })
end

begin
  results = []
  if ARGV.count < 3
    ids = read_index_file

    date_str = Date.today.strftime("%Y%m%d")
    matches = games("https://www.whoscored.com/livescores/data?d=#{date_str}&isSummary=true")
    matches.each do |m|
      next if ids.include?(m[:id])
      next unless m[:url]

      puts "#{NAMES_MAP[m[:home]] || m[:home]} - #{NAMES_MAP[m[:away]] || m[:away]}"
      match_xgs = xgs_new(
        (NAMES_MAP[m[:home]] || m[:home]).split(' ').join('_'),
        (NAMES_MAP[m[:away]] || m[:away]).split(' ').join('_'),
        m[:home_id],
        m[:away_id],
        ARGV[2] || starting_eleven( m[:url]),
        m[:tournament_id]
      )
      next unless match_xgs

      results << simulate_match(NAMES_MAP[m[:home]] || m[:home], NAMES_MAP[m[:away]] || m[:away], match_xgs)

      write_to_index_file(m[:id])
    rescue => e
      #binding.pry
      next
    end

  else
    puts "#{ARGV[0]} - #{ARGV[1]}"
    stats = xgs(ARGV[0], ARGV[1], starting_eleven(ARGV[2]))
    simulate_match(ARGV[0], ARGV[1], stats)
  end
ensure
  export_to_csv(results)
  print_proposals
end
