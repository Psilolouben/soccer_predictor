require 'nokogiri'
require 'httparty'
require 'watir'
require 'selenium-webdriver'
require 'pry'
require 'pry-byebug'
require 'capybara'
require 'active_support'
require 'active_support/time'
require 'distribution'
require 'mechanize'
require 'net/http'
require 'net/smtp'
require 'uri'
require 'json'
require 'csv'
require 'puppeteer-ruby'


# THRESHOLDS
THRESHOLDS = {
  UNDER_OVER_HALF_THRESHOLD: { index: [-1], value: 80 },
  SINGLE_THRESHOLD: { index: [2,4], value: 60 },
  DRAW_THRESHOLD: { index: [3], value: 35 },
  DOUBLE_THRESHOLD: { index: [5, 6, 7], value: 80 },
  UNDER_OVER_THRESHOLD: { index: [8, 9, 10, 11, 12, 13], value: 80 },
  GG_THRESHOLD: { index: [14], value: 80 },
  CORNER_THRESHOLD: { index: [-1], value: 80 },
  CARDS_THRESHOLD: { index: [16], value: 80 },
  PENALTY_THRESHOLD: { index: [-1], value: 80 },
  RED_CARD_THRESHOLD: { index: [-1], value: 80 },
  SCORER_THRESHOLD: { index: [-1], value: 60 }
}

# Minimum absolute edge (sim prob − implied prob) to surface a bet that misses
# its THRESHOLD but where the bookmaker is significantly mispricing the outcome.
EDGE_EXCEPTION_THRESHOLD = 0.10

# Per-player proposal thresholds
PLAYER_SCORER_THRESHOLD = 40.0  # anytime goalscorer: show if ≥40% probability
PLAYER_CARD_THRESHOLD   = 35.0  # player yellow card: show if ≥35% probability

# Half-time simulation: fraction of each team's expected goals that fall in HT.
# ~45% is well-supported by top-flight historical averages.
HT_GOAL_FACTOR = 0.45

# Half-time proposal thresholds
HT_SINGLE_THRESHOLD = 50.0
HT_DRAW_THRESHOLD   = 40.0
HT_OVER05_THRESHOLD = 70.0
HT_OVER15_THRESHOLD = 55.0
HT_GG_THRESHOLD     = 55.0


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

NUMBER_OF_SIMULATIONS = 100_00

def slugify(str)
  ActiveSupport::Inflector.transliterate(str.to_s).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/, '')
end

def preview_season
  y = Date.today.year
  Date.today.month <= 7 ? "#{y - 1}-#{y}" : "#{y}-#{y + 1}"
end

AVAILABLE_LEAGUES = {
    4 => 'LaLiga',
    5 => 'Serie A',
    3 => 'Bundesliga',
    22 => 'Ligue 1',
    12 => 'Champions League',
    30 => 'Europa League',
    20 => 'Premiership',
    21 => 'Liga Portugal',
    2 => 'Premier League',
    #7 => 'Championship',
    13 => 'Eredivisie',
    715 => 'Conference League',
    65 => 'Greek Super League',
    721 => 'World Cup Qualification UEFA',
    719 => 'World Cup Qualification CONMEBOL',
    717 => 'World Cup Qualification CONCACAF',
    95 => 'Brazil Serie A',
    739 => 'Womens Super League'
}

def games(url)
  @br = Watir::Browser.new :chrome, options: {
  args: [
    '--headless=new',
    '--disable-blink-features=AutomationControlled', # Disables WebDriver detection
    '--disable-infobars', # Removes "Chrome is being controlled by automated software"
    '--disable-extensions',
    '--no-sandbox',
    '--disable-dev-shm-usage',
    '--start-maximized',
    'user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    ]
  }
  @br.driver.manage.timeouts.page_load = 600 # Increase to 5 minutes
  @br.goto(url)

  a = JSON.parse(@br.elements.first.text)['tournaments'].
    select { |x| ARGV.include?('--all-leagues') || AVAILABLE_LEAGUES.keys.include?(x['tournamentId'])}.
    map { |x| x['matches'].map do |g|
      next if DateTime.now > DateTime.parse(g['startTime']).utc

      {
        id: g['id'],
        home: g['homeTeamName'],
        home_id: g['homeTeamId'],
        away: g['awayTeamName'],
        away_id: g['awayTeamId'],
        url: "https://www.whoscored.com/matches/#{g['id']}/preview/#{slugify(g['homeTeamCountryName'])}-#{slugify(x['tournamentName'])}-#{preview_season}-#{slugify(g['homeTeamName'])}-#{slugify(g['awayTeamName'])}",
        lineup_url: "https://www.whoscored.com/livescores/#{g['id']}/lineups",
        tournament_id: x['tournamentId'],
        tournament_name: x['tournamentName'],
        bet1:    g.dig('bets', 'home',    'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        betx:    g.dig('bets', 'draw',    'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet2:    g.dig('bets', 'away',    'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet_o15: g.dig('bets', 'over15',  'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet_u15: g.dig('bets', 'under15', 'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet_o25: g.dig('bets', 'over25',  'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet_u25: g.dig('bets', 'under25', 'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet_o35: g.dig('bets', 'over35',  'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet_u35: g.dig('bets', 'under35', 'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet_gg:   g.dig('bets', 'gg',      'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet_ng:   g.dig('bets', 'ng',      'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet_ht1:  g.dig('bets', 'htWin',   'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet_htx:  g.dig('bets', 'htDraw',  'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet_ht2:  g.dig('bets', 'htAway',  'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f
      }
    end
  }.flatten.compact
  a
rescue Watir::Wait::TimeoutError => e
  puts "Encountered a timeout, retrying..."
  retry
ensure
  @br.quit
end

def starting_eleven(url)
  @br = Watir::Browser.new :chrome, options: {
    args: [
      '--headless=new',
      '--disable-blink-features=AutomationControlled',
      '--disable-infobars',
      '--disable-extensions',
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--start-maximized',
      'user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    ]
  }
  @br.goto(url)

  a =  {
    home: JSON.parse(@br.elements.first.text).reject{|x| x['position'] == "Sub"}.select{|x| x['field']['displayName'] == 'Home'}.map{|x| x['name']},
    away: JSON.parse(@br.elements.first.text).reject{|x| x['position'] == "Sub"}.select{|x| x['field']['displayName'] == 'Away'}.map{|x| x['name']}
  }
  return nil if a[:home].count < 11 || a[:away].count < 11

  a
rescue JSON::ParserError
  return nil
rescue Selenium::WebDriver::Error::StaleElementReferenceError
  @br.quit
  puts "Encountered a stale element reference, retrying..."
  retry
rescue Net::ReadTimeout => e
  @br.quit
  puts "Encountered a timeout, retrying..."
  retry
rescue Watir::Wait::TimeoutError => e
  @br.quit
  puts "Encountered a timeout, retrying..."
  retry
rescue => e
  return nil
ensure
  @br.quit
end

def predicted_eleven(url)
  @br = Watir::Browser.new :chrome, options: {
    args: [
      '--headless=new',
      '--disable-blink-features=AutomationControlled',
      '--disable-infobars',
      '--disable-extensions',
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--start-maximized',
      'user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    ]
  }
  puts 'Fetching starting eleven...'
  @br.goto(url)
  return nil unless @br.title.include?('Preview')

  doc = Nokogiri::HTML(@br.html)
  names = doc.css('.player-name.player-link.cnt-oflow.rc').map(&:text)
  return nil if names.count < 22

  {
    home: names.take(11),
    away: names.reverse.take(11)
  }
rescue => e
  return nil
ensure
  @br.quit
end

def goal_and_assist(goal, assist)
  (goal + assist - (goal * assist)) * 100
end

# Scrapes corners/game and offsides/game for a team from their WhoScored HTML page.
# Returns [corners_pg, offsides_pg] as floats (0.0 on failure).
# With --discover-team-html: dumps page HTML sections to help identify selectors.
def scrape_team_corner_offside_stats(team_url, team_id, competition_id)
  @br.goto(team_url)
  sleep(3)  # allow JS to render

  if ARGV.include?('--discover-team-html')
    base_path = File.join(__dir__, "team_html_#{team_id}_base.txt")
    File.write(base_path, @br.html)
    puts "Base page HTML written to #{base_path}"
  end

  offsides_pg = 0.0

  # Offsides are in the Defensive tab (data-stat-name="offsideGivenPerGame").
  # Corners are not available anywhere in WhoScored team stats.
  tab_link = @br.link(text: 'Defensive')
  if ARGV.include?('--discover-team-html')
    puts "Tab 'defensive' exists: #{tab_link.exists?}"
  end

  if tab_link.present?
    tab_link.click
    sleep(2)

    if ARGV.include?('--discover-team-html')
      out_path = File.join(__dir__, "team_html_#{team_id}_defensive.txt")
      File.write(out_path, @br.html)
      puts "Defensive tab HTML written to #{out_path}"
    end

    doc   = Nokogiri::HTML(@br.html)
    table = doc.at_css('#statistics-team-table-defensive table')
    if table
      # Find offsides column index by header text (robust against CSS class renames)
      header_cells = table.css('thead th')
      off_idx = header_cells.find_index { |th| th.text.strip.downcase.include?('offside') }

      # Prefer the row matching competition_id in the tournament link href
      row = table.css('tbody tr').find { |tr| tr.at_css('a')&.[]('href').to_s.include?("/#{competition_id}/") }
      row ||= table.at_css('tbody tr')

      if row && off_idx
        cells = row.css('td')
        offsides_pg = cells[off_idx]&.text&.strip&.to_f || 0.0
      else
        # Fallback: try original CSS class selector
        td = row&.at_css('td.offsideGivenPerGame')
        offsides_pg = td&.text&.to_f || 0.0
      end
      puts "  team #{team_id}: row=#{row ? 'found' : 'nil'}, off_idx=#{off_idx.inspect}, offsides_pg=#{offsides_pg}"
    end
  end

  [offsides_pg]
rescue => e
  puts "scrape_team_corner_offside_stats error (team #{team_id}): #{e.message}"
  [0.0, 0.0]
end

def xgs_new(home_team, away_team, home_id, away_id, starting_eleven, competition_id, predicted_lineup = false)
  @br = Watir::Browser.new :chrome, options: {
    args: [
      '--headless=new',
      '--disable-blink-features=AutomationControlled',
      '--disable-infobars',
      '--disable-extensions',
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--start-maximized',
      'user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    ]
  }
  home_url = "https://www.whoscored.com/StatisticsFeed/1/GetPlayerStatistics?category=xg-stats&subcategory=summary&statsAccumulationType=0&tournamentOptions=#{competition_id}&isCurrent=true&playerId=&teamIds=#{home_id}&sortBy=xg&sortAscending=false&field=Home&isMinApp=false&page=&includeZeroValues=true&numberOfPlayersToPick=&incPens=true"
  away_url = "https://www.whoscored.com/StatisticsFeed/1/GetPlayerStatistics?category=xg-stats&subcategory=summary&statsAccumulationType=0&tournamentOptions=#{competition_id}&isCurrent=true&playerId=&teamIds=#{away_id}&sortBy=xg&sortAscending=false&field=Away&isMinApp=false&page=&includeZeroValues=true&numberOfPlayersToPick=&incPens=true"
  home_team_url = "https://www.whoscored.com/Teams/#{home_id}/Show"
  away_team_url = "https://www.whoscored.com/Teams/#{away_id}/Show"
  puts 'Fetching home xGs...'

  @br.goto(home_url)
  xgs_warning = false
  home_xgs = starting_eleven[:home].each_with_object({}) do |p, hsh|
    shots = (JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}&.first.try(:[], 'totalShots') || 0)
    apps = (JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}&.first.try(:[], 'apps')  || 0)
    hsh[p] = []
    hsh[p][0] = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}&.first.try(:[], 'xGPerShot') || 0
    hsh[p][1] = apps == 0 ? 0 : shots / apps.to_f
  end
  xgs_warning = true if home_xgs.count{ |_,v| v == 0} > 2
  return if home_xgs.values.all?{|x| x == [0,0]}

  home_cards_url = "https://www.whoscored.com/StatisticsFeed/1/GetPlayerStatistics?category=summary&subcategory=all&statsAccumulationType=0&isCurrent=true&playerId=&teamIds=#{home_id}&matchId=&stageId=&tournamentOptions=#{competition_id}&sortBy=Rating&sortAscending=&age=&ageComparisonType=&appearances=&appearancesComparisonType=&field=Home&nationality=&positionOptions=&timeOfTheGameEnd=&timeOfTheGameStart=&isMinApp=false&page=&includeZeroValues=true&numberOfPlayersToPick=&incPens="
  @br.goto(home_cards_url)
  puts 'Fetching home cards...'

  home_summary_raw = JSON.parse(@br.elements.first.text)['playerTableStats']

  if ARGV.include?('--discover-fields')
    sample = home_summary_raw.first
    if sample
      puts "\n=== WhoScored summary playerTableStats keys ==="
      puts sample.keys.sort.join(', ')
      puts "=== Sample values for first player: #{sample['name']} ==="
      sample.sort.each { |k, v| puts "  #{k}: #{v.inspect}" }
      puts "================================================\n"
    end
  end

  home_cards = starting_eleven[:home].each_with_object({}) do |p, hsh|
    player = home_summary_raw.select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}.first
    yellow = player.try(:[], 'yellowCard') || 0
    red    = player.try(:[], 'redCard')    || 0
    apps   = player.try(:[], 'apps')       || 0
    hsh[p] = apps.zero? ? 0 : ((yellow + red) / apps.to_f)
  end

  @br.goto(away_url)
  puts 'Fetching away xGs...'

  away_xgs = starting_eleven[:away].each_with_object({}) do |p, hsh|
    shots = (JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}&.first.try(:[], 'totalShots') || 0)
    apps = (JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}&.first.try(:[], 'apps')  || 0)
    hsh[p] = []
    hsh[p][0] = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}&.first.try(:[], 'xGPerShot') || 0
    hsh[p][1] = apps == 0 ? 0 : shots / apps.to_f
  end
  xgs_warning = true if away_xgs.count{ |_,v| v == 0} > 2
  return if away_xgs.values.all?{|x| x == [0,0]}

  away_cards_url = "https://www.whoscored.com/StatisticsFeed/1/GetPlayerStatistics?category=summary&subcategory=all&statsAccumulationType=0&isCurrent=true&playerId=&teamIds=#{away_id}&matchId=&stageId=&tournamentOptions=#{competition_id}&sortBy=Rating&sortAscending=&age=&ageComparisonType=&appearances=&appearancesComparisonType=&field=Away&nationality=&positionOptions=&timeOfTheGameEnd=&timeOfTheGameStart=&isMinApp=false&page=&includeZeroValues=true&numberOfPlayersToPick=&incPens="
  puts 'Fetching away cards...'

  @br.goto(away_cards_url)

  away_summary_raw = JSON.parse(@br.elements.first.text)['playerTableStats']
  away_cards = starting_eleven[:away].each_with_object({}) do |p, hsh|
    player = away_summary_raw.select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}.first
    yellow = player.try(:[], 'yellowCard') || 0
    red    = player.try(:[], 'redCard')    || 0
    apps   = player.try(:[], 'apps')       || 0
    hsh[p] = apps.zero? ? 0 : ((yellow + red) / apps.to_f)
  end

  # Fetch team-level offside stats from WhoScored team HTML page (corners not available on WhoScored)
  home_offsides_pg, = scrape_team_corner_offside_stats(home_team_url, home_id, competition_id)
  away_offsides_pg, = scrape_team_corner_offside_stats(away_team_url, away_id, competition_id)
  puts "Offsides pg — home: #{home_offsides_pg}, away: #{away_offsides_pg}"

  sleep(1)

  stats = {
    home_xgs: home_xgs,
    away_xgs: away_xgs,
    xgs_warning: xgs_warning,
    home_cards: home_cards,
    away_cards: away_cards,
    predicted_lineup: predicted_lineup,
    home_offsides_pg: home_offsides_pg,
    away_offsides_pg: away_offsides_pg
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

def write_proposals_csv(path, proposals, append: false)
  headers = ['Home', 'Away', '1', 'X', '2', '1X', 'X2', '12', 'O15', 'U15', 'O25', 'U25', 'O35', 'U35', 'GG', 'Missing XGS', 'Both Cards', 'Score',
             'Bet1', 'BetX', 'Bet2', 'BetO15', 'BetU15', 'BetO25', 'BetU25', 'BetO35', 'BetU35', 'BetGG', 'BetNG',
             'Edge1', 'EdgeX', 'Edge2', 'EdgeO15', 'EdgeU15', 'EdgeO25', 'EdgeU25', 'EdgeO35', 'EdgeU35', 'EdgeGG', 'EdgeNG',
             'Kelly1', 'KellyX', 'Kelly2', 'KellyO15', 'KellyU15', 'KellyO25', 'KellyU25', 'KellyO35', 'KellyU35', 'KellyGG', 'KellyNG']
  mode = append ? 'a' : 'w'
  CSV.open(path, mode, write_headers: (!append || !File.exist?(path)), headers: headers, col_sep: ';') do |csv|
    proposals.each do |game|
      csv << [
        game[:home_team], game[:away_team],
        game[:home], game[:draw], game[:away],
        game[:home].to_f + game[:draw].to_f, game[:draw].to_f + game[:away].to_f, game[:home].to_f + game[:away].to_f,
        game[:over15], game[:under15], game[:over25], game[:under25], game[:over35], game[:under35],
        game[:gg], game[:missing_xgs], game[:both_cards], game[:score],
        game[:bet1], game[:betx], game[:bet2],
        game[:bet_o15], game[:bet_u15], game[:bet_o25], game[:bet_u25], game[:bet_o35], game[:bet_u35],
        game[:bet_gg], game[:bet_ng],
        game[:home_edge], game[:draw_edge], game[:away_edge],
        game[:o15_edge], game[:u15_edge], game[:o25_edge], game[:u25_edge], game[:o35_edge], game[:u35_edge],
        game[:gg_edge], game[:ng_edge],
        game[:home_kelly], game[:draw_kelly], game[:away_kelly],
        game[:o15_kelly], game[:u15_kelly], game[:o25_kelly], game[:u25_kelly], game[:o35_kelly], game[:u35_kelly],
        game[:gg_kelly], game[:ng_kelly]
      ]
    end
  end
end

def export_to_csv(proposals)
  write_proposals_csv('bet_proposals.csv', proposals, append: true)

  # Archive a dated copy for retrospective accuracy tracking
  dated_path = File.join(__dir__, 'proposals', "#{Date.today.strftime('%Y-%m-%d')}.csv")
  Dir.mkdir(File.join(__dir__, 'proposals')) unless Dir.exist?(File.join(__dir__, 'proposals'))
  write_proposals_csv(dated_path, proposals, append: false)
  0
end

def export_offsides_csv(results)
  headers = ['Home', 'Away', 'OffsO35', 'OffsO45']
  CSV.open('offsides_proposals.csv', 'a',
           write_headers: !File.exist?('offsides_proposals.csv'),
           headers: headers, col_sep: ';') do |csv|
    results.each do |r|
      next unless r[:offsides_over35].to_f > 0
      csv << [r[:home_team], r[:away_team], r[:offsides_over35].round(1), r[:offsides_over45].round(1)]
    end
  end
end

def export_player_proposals_csv(results)
  headers = ['Home', 'Away', 'Team', 'Player', 'Market', 'Probability']
  CSV.open('player_proposals.csv', 'a',
           write_headers: !File.exist?('player_proposals.csv'),
           headers: headers, col_sep: ';') do |csv|
    results.each do |r|
      home_team = r[:home_team]
      away_team = r[:away_team]
      (r[:home_scorers]      || {}).each { |p, v| csv << [home_team, away_team, home_team, p, 'Scorer', v.round(2)] }
      (r[:away_scorers]      || {}).each { |p, v| csv << [home_team, away_team, away_team, p, 'Scorer', v.round(2)] }
      (r[:home_player_cards] || {}).each { |p, v| csv << [home_team, away_team, home_team, p, 'Card',   v.round(2)] }
      (r[:away_player_cards] || {}).each { |p, v| csv << [home_team, away_team, away_team, p, 'Card',   v.round(2)] }
    end
  end
end

def read_index_file
  File.readlines('index.txt', chomp: true).map(&:to_i)
end

def import_from_csv
  CSV.read("bet_proposals.csv", headers: true, col_sep: ';').map(&:to_h)
end

def build_proposals(predicted_lineups = {})
  return '' unless File.exist?('bet_proposals.csv')

  games = import_from_csv
  skip_cols = ['Missing XGS', 'Home', 'Away', 'Score',
               'Bet1', 'BetX', 'Bet2', 'BetO15', 'BetU15', 'BetO25', 'BetU25', 'BetO35', 'BetU35', 'BetGG', 'BetNG',
               'Edge1', 'EdgeX', 'Edge2', 'EdgeO15', 'EdgeU15', 'EdgeO25', 'EdgeU25', 'EdgeO35', 'EdgeU35', 'EdgeGG', 'EdgeNG',
               'Kelly1', 'KellyX', 'Kelly2', 'KellyO15', 'KellyU15', 'KellyO25', 'KellyU25', 'KellyO35', 'KellyU35', 'KellyGG', 'KellyNG']
  edge_col  = { '1' => 'Edge1', 'X' => 'EdgeX', '2' => 'Edge2',
                'O15' => 'EdgeO15', 'U15' => 'EdgeU15',
                'O25' => 'EdgeO25', 'U25' => 'EdgeU25',
                'O35' => 'EdgeO35', 'U35' => 'EdgeU35',
                'GG'  => 'EdgeGG',  'NG'  => 'EdgeNG' }
  kelly_col = { '1' => 'Kelly1', 'X' => 'KellyX', '2' => 'Kelly2',
                'O15' => 'KellyO15', 'U15' => 'KellyU15',
                'O25' => 'KellyO25', 'U25' => 'KellyU25',
                'O35' => 'KellyO35', 'U35' => 'KellyU35',
                'GG'  => 'KellyGG',  'NG'  => 'KellyNG' }

  # Load supplementary CSVs for unified per-match display
  ht_by_match = File.exist?('ht_proposals.csv') ?
    CSV.read('ht_proposals.csv', headers: true, col_sep: ';').map(&:to_h)
       .each_with_object({}) { |r, h| h["#{r['Home']}-#{r['Away']}"] = r } : {}
  pp_by_match = File.exist?('player_proposals.csv') ?
    CSV.read('player_proposals.csv', headers: true, col_sep: ';').map(&:to_h)
       .group_by { |r| "#{r['Home']}-#{r['Away']}" } : {}
  off_by_match = File.exist?('offsides_proposals.csv') ?
    CSV.read('offsides_proposals.csv', headers: true, col_sep: ';').map(&:to_h)
       .each_with_object({}) { |r, h| h["#{r['Home']}-#{r['Away']}"] = r } : {}

  by_match = {}
  games.each { |g| by_match["#{g['Home']}-#{g['Away']}"] = g }

  rows = by_match.filter_map do |_, g|
    next if g['Missing XGS'] == 'true'

    bets = []
    g.each_with_index do |(k, v), i|
      next if skip_cols.include?(k)
      threshold = THRESHOLDS.select { |_, t| t[:index].include?(i) }.values.first
      next unless threshold
      bets << { name: k, prob: v.to_f, tags: [:threshold] } if v.to_f >= threshold[:value]
    end

    edge_col.each do |market, ecol|
      next unless g[ecol] && g[ecol].to_f != 0
      edge = g[ecol].to_f
      next if edge.abs < EDGE_EXCEPTION_THRESHOLD
      existing = bets.find { |b| b[:name] == market }
      if existing
        existing[:tags] << :edge
      else
        prob = market == 'NG' ? (100 - g['GG'].to_f) : g[market].to_f
        bets << { name: market, prob: prob, tags: [:edge] }
      end
    end

    match_key = "#{g['Home']}-#{g['Away']}"
    next if bets.empty? && !ht_by_match[match_key] && !pp_by_match[match_key] && !off_by_match[match_key]

    { g: g, bets: bets, match_key: match_key }
  end

  return '' if rows.empty?

  rows.sort_by! { |row| -(row[:bets].map { |b| b[:prob] }.max || 0) }

  sep = '─' * 56
  lines = []
  rows.each do |row|
    g, bets, match_key = row[:g], row[:bets], row[:match_key]

    score_part, pct_part = g['Score'].to_s.split(':')
    score_str = pct_part ? "#{score_part} (#{pct_part.to_f.round(1)}%)" : ''

    odds = [g['Bet1'].to_f, g['BetX'].to_f, g['Bet2'].to_f]
    odds_str = odds.map { |o| o > 0 ? format('%.2f', o) : '-' }.join(' / ')

    lines << sep
    header = "#{g['Home']} vs #{g['Away']}"
    header += '  [PREDICTED XI]' if predicted_lineups[match_key]
    lines << "#{header.ljust(38)}  #{score_str}"
    lines << "  Odds: #{odds_str}"

    # Full-time bets
    bets.each do |bet|
      ek = edge_col[bet[:name]]
      kk = kelly_col[bet[:name]]
      edge  = ek ? g[ek].to_f : nil
      kelly = kk ? g[kk].to_f : nil

      tag_str = bet[:tags].map { |t|
        case t
        when :threshold then '[T]'
        when :edge      then edge && edge < 0 ? '[FADE]' : '[EDGE]'
        end
      }.join(' ')

      line = format('  %-8s %-10s %5.1f%%', tag_str, bet[:name], bet[:prob])
      if edge && edge != 0
        sign = edge > 0 ? '+' : ''
        line += format('   edge %s%.2f%%', sign, edge * 100)
        line += format('   kelly %.2f%%', kelly * 100) if kelly && kelly > 0
      end
      lines << line
    end

    # Half-time section
    if (ht = ht_by_match[match_key])
      ht_bets = []
      ht_bets << { name: 'HT Home', prob: ht['HT1'].to_f,   edge: ht['EdgeHT1'].to_f,  kelly: ht['KellyHT1'].to_f  } if ht['HT1'].to_f   >= HT_SINGLE_THRESHOLD
      ht_bets << { name: 'HT Draw', prob: ht['HTX'].to_f,   edge: ht['EdgeHTX'].to_f,  kelly: ht['KellyHTX'].to_f  } if ht['HTX'].to_f   >= HT_DRAW_THRESHOLD
      ht_bets << { name: 'HT Away', prob: ht['HT2'].to_f,   edge: ht['EdgeHT2'].to_f,  kelly: ht['KellyHT2'].to_f  } if ht['HT2'].to_f   >= HT_SINGLE_THRESHOLD
      ht_bets << { name: 'HT O0.5', prob: ht['HTO05'].to_f, edge: nil, kelly: nil }                                   if ht['HTO05'].to_f  >= HT_OVER05_THRESHOLD
      ht_bets << { name: 'HT O1.5', prob: ht['HTO15'].to_f, edge: nil, kelly: nil }                                   if ht['HTO15'].to_f  >= HT_OVER15_THRESHOLD
      ht_bets << { name: 'HT BTTS', prob: ht['HTGG'].to_f,  edge: nil, kelly: nil }                                   if ht['HTGG'].to_f   >= HT_GG_THRESHOLD

      unless ht_bets.empty?
        lines << format('  ─ Half Time: HT 1/X/2 %.1f%%/%.1f%%/%.1f%%   O0.5 %.1f%%   O1.5 %.1f%%',
                        ht['HT1'].to_f, ht['HTX'].to_f, ht['HT2'].to_f, ht['HTO05'].to_f, ht['HTO15'].to_f)
        ht_bets.each do |bet|
          line = format('  [T] %-10s %5.1f%%', bet[:name], bet[:prob])
          if bet[:edge].to_f != 0
            sign = bet[:edge] > 0 ? '+' : ''
            line += format('   edge %s%.2f%%', sign, bet[:edge] * 100)
            line += format('   kelly %.2f%%', bet[:kelly] * 100) if bet[:kelly].to_f > 0
          end
          lines << line
        end
      end
    end

    # Offsides section
    if (off = off_by_match[match_key])
      lines << format('  ─ Offsides  O3.5: %.1f%%   O4.5: %.1f%%', off['OffsO35'].to_f, off['OffsO45'].to_f)
    end

    # Player props section
    if (pp = pp_by_match[match_key])
      scorers = pp.select { |r| r['Market'] == 'Scorer' && r['Probability'].to_f >= PLAYER_SCORER_THRESHOLD }
                  .sort_by { |r| -r['Probability'].to_f }
      carders = pp.select { |r| r['Market'] == 'Card'   && r['Probability'].to_f >= PLAYER_CARD_THRESHOLD }
                  .sort_by { |r| -r['Probability'].to_f }
      if scorers.any?
        lines << "  ─ Scorer (>=#{PLAYER_SCORER_THRESHOLD.to_i}%)"
        scorers.each { |r| lines << format('      %-28s %-20s %5.1f%%', r['Player'], "(#{r['Team']})", r['Probability'].to_f) }
      end
      if carders.any?
        lines << "  ─ Yellow Card (>=#{PLAYER_CARD_THRESHOLD.to_i}%)"
        carders.each { |r| lines << format('      %-28s %-20s %5.1f%%', r['Player'], "(#{r['Team']})", r['Probability'].to_f) }
      end
    end
  end
  lines << sep
  lines.join("\n")
end

def print_proposals(predicted_lineups = {})
  body = build_proposals(predicted_lineups)
  puts body unless body.empty?
end

def build_player_proposals
  return '' unless File.exist?('player_proposals.csv') && !File.zero?('player_proposals.csv')
  rows = CSV.read('player_proposals.csv', headers: true, col_sep: ';').map(&:to_h)
  return '' if rows.empty?

  by_match = rows.group_by { |r| "#{r['Home']}-#{r['Away']}" }

  sep = '─' * 56
  lines = []

  by_match.each do |_, match_rows|
    scorers = match_rows.select { |r| r['Market'] == 'Scorer' && r['Probability'].to_f >= PLAYER_SCORER_THRESHOLD }
                        .sort_by { |r| -r['Probability'].to_f }
    carders = match_rows.select { |r| r['Market'] == 'Card'   && r['Probability'].to_f >= PLAYER_CARD_THRESHOLD }
                        .sort_by { |r| -r['Probability'].to_f }

    next if scorers.empty? && carders.empty?

    home = match_rows.first['Home']
    away = match_rows.first['Away']

    lines << sep
    lines << "#{home} vs #{away} — Player Props"

    unless scorers.empty?
      lines << "  Anytime Scorer (>=#{PLAYER_SCORER_THRESHOLD.to_i}%):"
      scorers.each do |r|
        lines << format('    %-28s %-22s %5.1f%%', r['Player'], "(#{r['Team']})", r['Probability'].to_f)
      end
    end

    unless carders.empty?
      lines << "  Yellow Card (>=#{PLAYER_CARD_THRESHOLD.to_i}%):"
      carders.each do |r|
        lines << format('    %-28s %-22s %5.1f%%', r['Player'], "(#{r['Team']})", r['Probability'].to_f)
      end
    end
  end

  return '' if lines.empty?
  lines << sep
  lines.join("\n")
end

def print_player_proposals
  body = build_player_proposals
  puts body unless body.empty?
end

def export_ht_proposals_csv(results)
  headers = ['Home', 'Away', 'HT1', 'HTX', 'HT2', 'HTO05', 'HTO15', 'HTGG',
             'BetHT1', 'BetHTX', 'BetHT2',
             'EdgeHT1', 'EdgeHTX', 'EdgeHT2',
             'KellyHT1', 'KellyHTX', 'KellyHT2']
  CSV.open('ht_proposals.csv', 'a',
           write_headers: !File.exist?('ht_proposals.csv'),
           headers: headers, col_sep: ';') do |csv|
    results.each do |r|
      csv << [
        r[:home_team], r[:away_team],
        r[:ht_home]&.round(1), r[:ht_draw]&.round(1), r[:ht_away]&.round(1),
        r[:ht_over05]&.round(1), r[:ht_over15]&.round(1), r[:ht_gg]&.round(1),
        r[:bet_ht1], r[:bet_htx], r[:bet_ht2],
        r[:ht1_edge], r[:htx_edge], r[:ht2_edge],
        r[:ht1_kelly], r[:htx_kelly], r[:ht2_kelly]
      ]
    end
  end
end

def build_ht_proposals
  return '' unless File.exist?('ht_proposals.csv') && !File.zero?('ht_proposals.csv')
  rows = CSV.read('ht_proposals.csv', headers: true, col_sep: ';').map(&:to_h)
  return '' if rows.empty?

  sep = '─' * 56
  lines = []

  rows.each do |r|
    bets = []
    bets << { name: 'HT Home',   prob: r['HT1'].to_f,   edge: r['EdgeHT1'].to_f,   kelly: r['KellyHT1'].to_f  } if r['HT1'].to_f   >= HT_SINGLE_THRESHOLD
    bets << { name: 'HT Draw',   prob: r['HTX'].to_f,   edge: r['EdgeHTX'].to_f,   kelly: r['KellyHTX'].to_f  } if r['HTX'].to_f   >= HT_DRAW_THRESHOLD
    bets << { name: 'HT Away',   prob: r['HT2'].to_f,   edge: r['EdgeHT2'].to_f,   kelly: r['KellyHT2'].to_f  } if r['HT2'].to_f   >= HT_SINGLE_THRESHOLD
    bets << { name: 'HT O0.5',   prob: r['HTO05'].to_f, edge: nil, kelly: nil }                                  if r['HTO05'].to_f  >= HT_OVER05_THRESHOLD
    bets << { name: 'HT O1.5',   prob: r['HTO15'].to_f, edge: nil, kelly: nil }                                  if r['HTO15'].to_f  >= HT_OVER15_THRESHOLD
    bets << { name: 'HT BTTS',   prob: r['HTGG'].to_f,  edge: nil, kelly: nil }                                  if r['HTGG'].to_f   >= HT_GG_THRESHOLD

    next if bets.empty?

    lines << sep
    lines << "#{r['Home']} vs #{r['Away']} — Half Time"
    lines << format('  HT 1/X/2: %.1f%% / %.1f%% / %.1f%%', r['HT1'].to_f, r['HTX'].to_f, r['HT2'].to_f)
    lines << format('  HT O0.5: %.1f%%   HT O1.5: %.1f%%   HT BTTS: %.1f%%', r['HTO05'].to_f, r['HTO15'].to_f, r['HTGG'].to_f)

    bets.each do |bet|
      line = format('  [T] %-10s %5.1f%%', bet[:name], bet[:prob])
      if bet[:edge] && bet[:edge] != 0
        sign = bet[:edge] > 0 ? '+' : ''
        line += format('   edge %s%.2f%%', sign, bet[:edge] * 100)
        line += format('   kelly %.2f%%', bet[:kelly] * 100) if bet[:kelly].to_f > 0
      end
      lines << line
    end
  end

  return '' if lines.empty?
  lines << sep
  lines.join("\n")
end

def print_ht_proposals
  body = build_ht_proposals
  puts body unless body.empty?
end

# Returns [edge, kelly] for a market. Returns [nil, nil] if odds are missing/invalid.
# sim_pct is 0–100, odds is decimal (e.g. 2.50).
def market_edge_kelly(sim_pct, odds)
  return [nil, nil] unless odds.to_f > 1
  prob  = sim_pct / 100.0
  edge  = (prob - (1.0 / odds)).round(4)
  kelly = edge > 0 ? (edge / (odds - 1)).round(4) : 0
  [edge, kelly]
end

def evaluate_model
  files = Dir.glob(File.join(__dir__, 'proposals', '*.csv')).sort.reject do |f|
    File.basename(f, '.csv') == Date.today.strftime('%Y-%m-%d')
  end

  return "No archived proposals found. Run the predictor first to build history.\n" if files.empty?

  api_key = ENV['FOOTBALL_DATA_API_KEY']
  return "Set FOOTBALL_DATA_API_KEY env var (free key from football-data.org).\n" unless api_key

  normalize = ->(name) {
    ActiveSupport::Inflector.transliterate(name.to_s)
      .downcase.gsub(/[^a-z0-9]/, ' ').gsub(/\s+/, ' ').strip
  }
  bigrams   = ->(s) { (0...s.length - 1).map { |i| s[i, 2] }.to_set }
  sim       = ->(a, b) {
    ba = bigrams.(a); bb = bigrams.(b)
    return 0.0 if (ba | bb).empty?
    (ba & bb).size.to_f / (ba | bb).size
  }

  stats = Hash.new { |h, k| h[k] = { correct: 0, total: 0 } }
  threshold_bets = []
  skipped = 0

  files.each do |file|
    date = File.basename(file, '.csv')
    response = HTTParty.get(
      'https://api.football-data.org/v4/matches',
      headers: { 'X-Auth-Token' => api_key },
      query:   { dateFrom: date, dateTo: date }
    )
    next unless response.success?

    api_results = (response.parsed_response['matches'] || [])
      .select { |m| m['status'] == 'FINISHED' }
      .map do |m|
        {
          home:       m.dig('homeTeam', 'name').to_s,
          home_short: m.dig('homeTeam', 'shortName').to_s,
          away:       m.dig('awayTeam', 'name').to_s,
          away_short: m.dig('awayTeam', 'shortName').to_s,
          home_goals: m.dig('score', 'fullTime', 'home').to_i,
          away_goals: m.dig('score', 'fullTime', 'away').to_i,
        }
      end

    CSV.foreach(file, headers: true, col_sep: ';') do |row|
      csv_home = row['Home'].to_s.strip
      csv_away = row['Away'].to_s.strip

      candidate = nil
      api_results.each do |r|
        sh = sim.(normalize.(csv_home), normalize.(r[:home])) +
             sim.(normalize.(csv_home), normalize.(r[:home_short]))
        sa = sim.(normalize.(csv_away), normalize.(r[:away])) +
             sim.(normalize.(csv_away), normalize.(r[:away_short]))
        combined = sh + sa
        if candidate.nil? || combined > candidate[:score]
          candidate = { result: r, score: combined }
        end
      end

      if candidate.nil? || candidate[:score] < 0.8
        skipped += 1
        next
      end

      hg     = candidate[:result][:home_goals]
      ag     = candidate[:result][:away_goals]
      total  = hg + ag
      result = hg > ag ? '1' : hg < ag ? '2' : 'X'

      # Result prediction (highest probability among 1/X/2)
      probs     = { '1' => row['1'].to_f, 'X' => row['X'].to_f, '2' => row['2'].to_f }
      predicted = probs.max_by { |_, v| v }&.first
      stats[:result][:correct] += 1 if predicted == result
      stats[:result][:total]   += 1

      # Confident win prediction (>60% for either team)
      if row['1'].to_f > 60 || row['2'].to_f > 60
        predicted_win = row['1'].to_f > row['2'].to_f ? '1' : '2'
        stats[:result_confident][:correct] += 1 if predicted_win == result
        stats[:result_confident][:total]   += 1
      end

      { o15: total > 1.5, u15: total <= 1.5,
        o25: total > 2.5, u25: total <= 2.5,
        o35: total > 3.5, u35: total <= 3.5 }.each do |key, actual|
        stats[key][:correct] += 1 if actual
        stats[key][:total]   += 1
      end

      stats[:gg][:correct] += 1 if hg > 0 && ag > 0
      stats[:gg][:total]   += 1

      # Threshold bets: any row where Bet* columns were stored
      [
        ['Bet1', :home_win], ['BetX', :draw], ['Bet2', :away_win],
        ['BetO15', :o15], ['BetU15', :u15],
        ['BetO25', :o25], ['BetU25', :u25],
        ['BetO35', :o35], ['BetU35', :u35],
        ['BetGG',  :gg],  ['BetNG',  :ng],
      ].each do |col, key|
        odds = row[col]&.to_f
        next if odds.nil? || odds <= 1
        actual_outcome = { home_win: result == '1', draw: result == 'X', away_win: result == '2',
                           o15: total > 1.5, u15: total <= 1.5,
                           o25: total > 2.5, u25: total <= 2.5,
                           o35: total > 3.5, u35: total <= 3.5,
                           gg: hg > 0 && ag > 0, ng: hg == 0 || ag == 0 }[key]
        threshold_bets << { odds: odds, won: actual_outcome }
      end
    end
  end

  labels = {
    result:           'Result (1/X/2)   ',
    result_confident: 'Result (>60% win)',
    o15:              'Over 1.5         ',
    u15:              'Under 1.5        ',
    o25:              'Over 2.5         ',
    u25:              'Under 2.5        ',
    o35:              'Over 3.5         ',
    u35:              'Under 3.5        ',
    gg:               'GG (both score)  ',
  }

  lines = []
  lines << "#{'═' * 48}"
  lines << '  MODEL ACCURACY REPORT'
  lines << "  #{files.size} date(s) evaluated  |  #{skipped} unmatched"
  lines << "#{'═' * 48}"
  lines << ''
  labels.each do |key, label|
    s = stats[key]
    if s[:total] > 0
      pct = (s[:correct] / s[:total].to_f * 100).round(1)
      lines << "#{label}  #{s[:correct]}/#{s[:total]}  (#{pct}%)"
    else
      lines << "#{label}  N/A"
    end
  end

  if threshold_bets.any?
    wins     = threshold_bets.count { |b| b[:won] }
    total_b  = threshold_bets.size
    roi      = threshold_bets.sum { |b| b[:won] ? b[:odds] - 1 : -1 }
    avg_odds = threshold_bets.sum { |b| b[:odds] } / total_b.to_f
    lines << ''
    lines << "Threshold bets:  #{wins}/#{total_b}  (#{(wins.to_f / total_b * 100).round(1)}%)"
    lines << "Avg odds: #{avg_odds.round(2)}  |  Flat-stake ROI: #{roi > 0 ? '+' : ''}#{roi.round(2)} units"
  end

  lines << ''
  lines.join("\n")
end

GMAIL_ADDRESS = 'marky.rigas@gmail.com'.freeze
EMAIL_RECIPIENTS = [GMAIL_ADDRESS, 'christos.deliyannis@gmail.com'].freeze

def format_results_for_prompt(results)
  lines = []
  results.each do |r|
    lines << "#{r[:home_team]} vs #{r[:away_team]}#{r[:predicted_lineup] ? ' [PREDICTED XI]' : ''}"
    lines << "  1/X/2: #{r[:home].round(1)}% / #{r[:draw].round(1)}% / #{r[:away].round(1)}%"
    lines << "  O1.5: #{r[:over15].round(1)}%  U1.5: #{r[:under15].round(1)}%  O2.5: #{r[:over25].round(1)}%  U2.5: #{r[:under25].round(1)}%  O3.5: #{r[:over35].round(1)}%  U3.5: #{r[:under35].round(1)}%"
    lines << "  GG: #{r[:gg].round(1)}%  NG: #{(100.0 - r[:gg]).round(1)}%  Both Cards: #{r[:both_cards].round(1)}%  2or3 Goals: #{r[:two_three].round(1)}%  Most likely score: #{r[:score]}"
    lines << "  Missing XGS: #{r[:missing_xgs]}"

    all_scorers = ((r[:home_scorers] || {}).merge(r[:away_scorers] || {}))
                    .select { |_, v| v >= PLAYER_SCORER_THRESHOLD }
                    .sort_by { |_, v| -v }.first(5)
    lines << "  Top scorers: #{all_scorers.map { |n, v| "#{n} #{v.round(1)}%" }.join(', ')}" unless all_scorers.empty?

    all_carders = ((r[:home_player_cards] || {}).merge(r[:away_player_cards] || {}))
                    .select { |_, v| v >= PLAYER_CARD_THRESHOLD }
                    .sort_by { |_, v| -v }.first(5)
    lines << "  Card risks:  #{all_carders.map { |n, v| "#{n} #{v.round(1)}%" }.join(', ')}" unless all_carders.empty?

    lines << format('  HT 1/X/2: %.1f%% / %.1f%% / %.1f%%   HT O0.5: %.1f%%   HT O1.5: %.1f%%   HT GG: %.1f%%',
                    r[:ht_home].to_f, r[:ht_draw].to_f, r[:ht_away].to_f,
                    r[:ht_over05].to_f, r[:ht_over15].to_f, r[:ht_gg].to_f)
    if r[:offsides_over35].to_f > 0
      lines << format('  Offsides O3.5: %.1f%%  O4.5: %.1f%%',
                      r[:offsides_over35].to_f, r[:offsides_over45].to_f)
    end

    odds_parts = []
    odds_parts << "1=#{r[:bet1]}" if r[:bet1].to_f > 1
    odds_parts << "X=#{r[:betx]}" if r[:betx].to_f > 1
    odds_parts << "2=#{r[:bet2]}" if r[:bet2].to_f > 1
    odds_parts << "O1.5=#{r[:bet_o15]}" if r[:bet_o15].to_f > 1
    odds_parts << "U1.5=#{r[:bet_u15]}" if r[:bet_u15].to_f > 1
    odds_parts << "O2.5=#{r[:bet_o25]}" if r[:bet_o25].to_f > 1
    odds_parts << "U2.5=#{r[:bet_u25]}" if r[:bet_u25].to_f > 1
    odds_parts << "O3.5=#{r[:bet_o35]}" if r[:bet_o35].to_f > 1
    odds_parts << "U3.5=#{r[:bet_u35]}" if r[:bet_u35].to_f > 1
    odds_parts << "GG=#{r[:bet_gg]}"    if r[:bet_gg].to_f > 1
    odds_parts << "NG=#{r[:bet_ng]}"    if r[:bet_ng].to_f > 1
    lines << "  Odds: #{odds_parts.join('  ')}" unless odds_parts.empty?

    edge_parts = []
    edge_parts << "1=#{(r[:home_edge]*100).round(1)}pp"   if r[:home_edge]
    edge_parts << "X=#{(r[:draw_edge]*100).round(1)}pp"   if r[:draw_edge]
    edge_parts << "2=#{(r[:away_edge]*100).round(1)}pp"   if r[:away_edge]
    edge_parts << "O1.5=#{(r[:o15_edge]*100).round(1)}pp" if r[:o15_edge]
    edge_parts << "U1.5=#{(r[:u15_edge]*100).round(1)}pp" if r[:u15_edge]
    edge_parts << "O2.5=#{(r[:o25_edge]*100).round(1)}pp" if r[:o25_edge]
    edge_parts << "U2.5=#{(r[:u25_edge]*100).round(1)}pp" if r[:u25_edge]
    edge_parts << "O3.5=#{(r[:o35_edge]*100).round(1)}pp" if r[:o35_edge]
    edge_parts << "U3.5=#{(r[:u35_edge]*100).round(1)}pp" if r[:u35_edge]
    edge_parts << "GG=#{(r[:gg_edge]*100).round(1)}pp"    if r[:gg_edge]
    edge_parts << "NG=#{(r[:ng_edge]*100).round(1)}pp"    if r[:ng_edge]
    edge_parts << "HT1=#{(r[:ht1_edge]*100).round(1)}pp"  if r[:ht1_edge]
    edge_parts << "HTX=#{(r[:htx_edge]*100).round(1)}pp"  if r[:htx_edge]
    edge_parts << "HT2=#{(r[:ht2_edge]*100).round(1)}pp"  if r[:ht2_edge]
    lines << "  Edge: #{edge_parts.join('  ')}" unless edge_parts.empty?

    kelly_parts = []
    kelly_parts << "1=#{(r[:home_kelly]*100).round(2)}%"   if r[:home_kelly].to_f > 0
    kelly_parts << "X=#{(r[:draw_kelly]*100).round(2)}%"   if r[:draw_kelly].to_f > 0
    kelly_parts << "2=#{(r[:away_kelly]*100).round(2)}%"   if r[:away_kelly].to_f > 0
    kelly_parts << "O1.5=#{(r[:o15_kelly]*100).round(2)}%" if r[:o15_kelly].to_f > 0
    kelly_parts << "U1.5=#{(r[:u15_kelly]*100).round(2)}%" if r[:u15_kelly].to_f > 0
    kelly_parts << "O2.5=#{(r[:o25_kelly]*100).round(2)}%" if r[:o25_kelly].to_f > 0
    kelly_parts << "U2.5=#{(r[:u25_kelly]*100).round(2)}%" if r[:u25_kelly].to_f > 0
    kelly_parts << "O3.5=#{(r[:o35_kelly]*100).round(2)}%" if r[:o35_kelly].to_f > 0
    kelly_parts << "U3.5=#{(r[:u35_kelly]*100).round(2)}%" if r[:u35_kelly].to_f > 0
    kelly_parts << "GG=#{(r[:gg_kelly]*100).round(2)}%"    if r[:gg_kelly].to_f > 0
    kelly_parts << "NG=#{(r[:ng_kelly]*100).round(2)}%"    if r[:ng_kelly].to_f > 0
    kelly_parts << "HT1=#{(r[:ht1_kelly]*100).round(2)}%"  if r[:ht1_kelly].to_f > 0
    kelly_parts << "HTX=#{(r[:htx_kelly]*100).round(2)}%"  if r[:htx_kelly].to_f > 0
    kelly_parts << "HT2=#{(r[:ht2_kelly]*100).round(2)}%"  if r[:ht2_kelly].to_f > 0
    lines << "  Kelly: #{kelly_parts.join('  ')}" unless kelly_parts.empty?

    lines << ''
  end
  lines.join("\n")
end

def format_csvs_for_prompt
  return '' unless File.exist?('bet_proposals.csv')

  rows = CSV.read('bet_proposals.csv', headers: true, col_sep: ';').map(&:to_h)
  ht_by_match  = File.exist?('ht_proposals.csv') ?
    CSV.read('ht_proposals.csv', headers: true, col_sep: ';').map(&:to_h)
       .each_with_object({}) { |r, h| h["#{r['Home']}-#{r['Away']}"] = r } : {}
  off_by_match = File.exist?('offsides_proposals.csv') ?
    CSV.read('offsides_proposals.csv', headers: true, col_sep: ';').map(&:to_h)
       .each_with_object({}) { |r, h| h["#{r['Home']}-#{r['Away']}"] = r } : {}
  pp_by_match  = File.exist?('player_proposals.csv') ?
    CSV.read('player_proposals.csv', headers: true, col_sep: ';').map(&:to_h)
       .group_by { |r| "#{r['Home']}-#{r['Away']}" } : {}

  by_match = {}
  rows.each { |r| by_match["#{r['Home']}-#{r['Away']}"] = r }

  lines = []
  by_match.each do |match_key, r|
    next if r['Missing XGS'] == 'true'
    lines << "#{r['Home']} vs #{r['Away']}"
    lines << "  1/X/2: #{r['1'].to_f.round(1)}% / #{r['X'].to_f.round(1)}% / #{r['2'].to_f.round(1)}%"
    lines << "  O1.5/O2.5/O3.5: #{r['O15'].to_f.round(1)}% / #{r['O25'].to_f.round(1)}% / #{r['O35'].to_f.round(1)}%"
    lines << "  GG: #{r['GG'].to_f.round(1)}%   Both Cards: #{r['Both Cards'].to_f.round(1)}%   Most likely score: #{r['Score']}"
    lines << "  Missing XGS: #{r['Missing XGS']}"

    odds_parts = []
    [['Bet1','1'], ['BetX','X'], ['Bet2','2'], ['BetO15','O1.5'], ['BetU15','U1.5'],
     ['BetO25','O2.5'], ['BetU25','U2.5'], ['BetO35','O3.5'], ['BetU35','U3.5'],
     ['BetGG','GG'], ['BetNG','NG']].each do |col, label|
      odds_parts << "#{label}=#{r[col]}" if r[col].to_f > 1
    end
    lines << "  Odds: #{odds_parts.join('  ')}" unless odds_parts.empty?

    edge_parts = []
    [['Edge1','1'], ['EdgeX','X'], ['Edge2','2'], ['EdgeO25','O2.5'],
     ['EdgeGG','GG'], ['EdgeNG','NG']].each do |col, label|
      edge_parts << "#{label}=#{(r[col].to_f * 100).round(1)}pp" if r[col].to_f != 0
    end
    lines << "  Edge: #{edge_parts.join('  ')}" unless edge_parts.empty?

    kelly_parts = []
    [['Kelly1','1'], ['KellyX','X'], ['Kelly2','2'], ['KellyO25','O2.5'],
     ['KellyGG','GG']].each do |col, label|
      kelly_parts << "#{label}=#{(r[col].to_f * 100).round(2)}%" if r[col].to_f > 0
    end
    lines << "  Kelly: #{kelly_parts.join('  ')}" unless kelly_parts.empty?

    if (ht = ht_by_match[match_key])
      lines << format('  HT 1/X/2: %.1f%% / %.1f%% / %.1f%%   HT O0.5: %.1f%%   HT O1.5: %.1f%%',
                      ht['HT1'].to_f, ht['HTX'].to_f, ht['HT2'].to_f, ht['HTO05'].to_f, ht['HTO15'].to_f)
      ht_odds = []
      ht_odds << "HT1=#{ht['BetHT1']}" if ht['BetHT1'].to_f > 1
      ht_odds << "HTX=#{ht['BetHTX']}" if ht['BetHTX'].to_f > 1
      ht_odds << "HT2=#{ht['BetHT2']}" if ht['BetHT2'].to_f > 1
      lines << "  HT Odds: #{ht_odds.join('  ')}" unless ht_odds.empty?
      ht_edge = []
      ht_edge << "HT1=#{(ht['EdgeHT1'].to_f * 100).round(1)}pp" if ht['EdgeHT1'].to_f != 0
      ht_edge << "HTX=#{(ht['EdgeHTX'].to_f * 100).round(1)}pp" if ht['EdgeHTX'].to_f != 0
      ht_edge << "HT2=#{(ht['EdgeHT2'].to_f * 100).round(1)}pp" if ht['EdgeHT2'].to_f != 0
      lines << "  HT Edge: #{ht_edge.join('  ')}" unless ht_edge.empty?
    end

    if (off = off_by_match[match_key])
      lines << format('  Offsides O3.5: %.1f%%  O4.5: %.1f%%', off['OffsO35'].to_f, off['OffsO45'].to_f)
    end

    if (pp = pp_by_match[match_key])
      scorers = pp.select { |pr| pr['Market'] == 'Scorer' && pr['Probability'].to_f >= PLAYER_SCORER_THRESHOLD }
                  .sort_by { |pr| -pr['Probability'].to_f }.first(5)
      carders = pp.select { |pr| pr['Market'] == 'Card'   && pr['Probability'].to_f >= PLAYER_CARD_THRESHOLD }
                  .sort_by { |pr| -pr['Probability'].to_f }.first(5)
      lines << "  Top scorers: #{scorers.map { |pr| "#{pr['Player']} #{pr['Probability'].to_f.round(1)}%" }.join(', ')}" unless scorers.empty?
      lines << "  Card risks:  #{carders.map { |pr| "#{pr['Player']} #{pr['Probability'].to_f.round(1)}%" }.join(', ')}" unless carders.empty?
    end

    lines << ''
  end
  lines.join("\n")
end

def ask_claude_for_tips_from_csvs
  sim_data = format_csvs_for_prompt
  return puts("No CSV data found — run the simulation first.") if sim_data.strip.empty?

  template = File.read(File.join(__dir__, 'prompts/tips_prompt.md'))
  prompt   = template.gsub('{{SIM_DATA}}', sim_data)

  puts "\nAsking Claude for tips (from existing CSVs)..."
  output = IO.popen(['claude', '-p', prompt], err: :close, &:read)

  if $?.success? && !output.strip.empty?
    sep = '═' * 56
    puts "\n#{sep}"
    puts "  AI TIPS"
    puts sep
    puts output.strip
    puts sep
  else
    puts "Claude CLI returned no output. Is `claude` installed and logged in?"
  end
rescue Errno::ENOENT
  puts "`claude` CLI not found in PATH — skipping tips"
rescue => e
  puts "Tips failed: #{e.message}"
end

def ask_claude_for_tips(results)
  return nil if results.empty?

  sim_data = format_results_for_prompt(results)

  template = File.read(File.join(__dir__, 'prompts/tips_prompt.md'))
  prompt = template.gsub('{{SIM_DATA}}', sim_data)

  puts "\nAsking Claude for tips..."
  output = IO.popen(['claude', '-p', prompt], err: :close, &:read)

  if $?.success? && !output.strip.empty?
    sep = '═' * 56
    formatted = "\n#{sep}\n  AI TIPS\n#{sep}\n#{output.strip}\n#{sep}"
    puts formatted
    formatted
  else
    puts "Claude CLI returned no output. Is `claude` installed and logged in?"
    nil
  end
rescue Errno::ENOENT
  puts "`claude` CLI not found in PATH — skipping tips"
  nil
rescue => e
  puts "Tips failed: #{e.message}"
  nil
end

def send_proposals_email(body)
  password = ENV['GMAIL_APP_PASSWORD']
  unless password
    puts "GMAIL_APP_PASSWORD env var not set — skipping email"
    return
  end

  date_str = Date.today.strftime('%Y-%m-%d')
  message = <<~MSG
    From: Soccer Predictor <#{GMAIL_ADDRESS}>
    To: #{EMAIL_RECIPIENTS.join(', ')}
    Subject: Bet proposals #{date_str}
    Content-Type: text/plain; charset=UTF-8

    #{body}
  MSG

  smtp = Net::SMTP.new('smtp.gmail.com', 587)
  smtp.enable_starttls
  smtp.start('localhost', GMAIL_ADDRESS, password, :login) do |s|
    s.send_message(message, GMAIL_ADDRESS, EMAIL_RECIPIENTS)
  end
  puts "Email sent to #{EMAIL_RECIPIENTS.join(', ')}"
rescue => e
  puts "Email failed: #{e.message}"
end

def simulate_match(home_team, away_team, stats)
  res = {
    home_team: home_team,
    away_team: away_team,
    missing_xgs: stats[:xgs_warning],
    predicted_lineup: stats[:predicted_lineup],
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
    ht_home: 0, ht_draw: 0, ht_away: 0,
    ht_over05: 0, ht_over15: 0, ht_gg: 0,
    offsides_over35: 0, offsides_over45: 0,
    score: ''
  }

  home_scorer_count = Hash.new(0)
  away_scorer_count = Hash.new(0)
  home_card_count   = Hash.new(0)
  away_card_count   = Hash.new(0)
  scores = []

  puts "Simulating games..."

  NUMBER_OF_SIMULATIONS.times do
    home_xg_stats = stats[:home_xgs].transform_values do |(xg_per_shot, avg_shots)|
      shots = Distribution::Poisson.rng(avg_shots)
      goals = Array.new(shots) { rand < xg_per_shot ? 1 : 0 }.sum
      goals
    end.select { |_, goals| goals > 0 }
    away_xg_stats = stats[:away_xgs].transform_values do |(xg_per_shot, avg_shots)|
      shots = Distribution::Poisson.rng(avg_shots)
      goals = Array.new(shots) { rand < xg_per_shot ? 1 : 0 }.sum
      goals
    end.select { |_, goals| goals > 0 }

    #home_assist_stats = stats[:home_xas].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    #away_assist_stats = stats[:away_xas].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    home_yellow_cards = stats[:home_cards].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    away_yellow_cards = stats[:away_cards].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    #home = ((home_xg_stats.sum{ |_, v| v } + away_xga) / 2.0).round
    home = ((home_xg_stats.sum{ |_, v| v })).round
    away = ((away_xg_stats.sum{ |_, v| v })).round
    #away = ((away_xg_stats.sum{ |_, v| v } + home_xga ) / 2.0).round
    # Track anytime scorers (players who scored ≥1 goal in this sim)
    home_xg_stats.each_key { |p| home_scorer_count[p] += 1 }
    away_xg_stats.each_key { |p| away_scorer_count[p] += 1 }
    # Track per-player cards
    home_yellow_cards.each_key { |p| home_card_count[p] += 1 }
    away_yellow_cards.each_key { |p| away_card_count[p] += 1 }

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

    # Half-time simulation: rescale avg shots by HT_GOAL_FACTOR
    ht_home_goals = stats[:home_xgs].sum do |(_, (xg_per_shot, avg_shots))|
      shots = Distribution::Poisson.rng(avg_shots * HT_GOAL_FACTOR)
      Array.new(shots) { rand < xg_per_shot ? 1 : 0 }.sum
    end
    ht_away_goals = stats[:away_xgs].sum do |(_, (xg_per_shot, avg_shots))|
      shots = Distribution::Poisson.rng(avg_shots * HT_GOAL_FACTOR)
      Array.new(shots) { rand < xg_per_shot ? 1 : 0 }.sum
    end

    if ht_home_goals > ht_away_goals
      res[:ht_home] += 1
    elsif ht_home_goals == ht_away_goals
      res[:ht_draw] += 1
    else
      res[:ht_away] += 1
    end
    res[:ht_over05] += 1 if ht_home_goals + ht_away_goals >= 1
    res[:ht_over15] += 1 if ht_home_goals + ht_away_goals >= 2
    res[:ht_gg]     += 1 if ht_home_goals > 0 && ht_away_goals > 0

    # Offsides simulation
    if stats[:home_offsides_pg].to_f > 0 || stats[:away_offsides_pg].to_f > 0
      total_offsides = Distribution::Poisson.rng(stats[:home_offsides_pg].to_f) +
                       Distribution::Poisson.rng(stats[:away_offsides_pg].to_f)
      res[:offsides_over35] += 1 if total_offsides > 3.5
      res[:offsides_over45] += 1 if total_offsides > 4.5
    end
  end

  pct = NUMBER_OF_SIMULATIONS / 100.0
  res[:home_scorers]      = home_scorer_count.transform_values { |v| v / pct }
  res[:away_scorers]      = away_scorer_count.transform_values { |v| v / pct }
  res[:home_player_cards] = home_card_count.transform_values   { |v| v / pct }
  res[:away_player_cards] = away_card_count.transform_values   { |v| v / pct }
  res[:score] = scores.tally.transform_values{|v| v/(NUMBER_OF_SIMULATIONS.to_f / 100)}.sort_by{|_, v| v}.reverse.first.join(':')

  return res.merge(res.except(:home_team, :away_team, :missing_xgs, :predicted_lineup,
                               :home_scorers, :away_scorers, :home_player_cards, :away_player_cards,
                               :score).transform_values{ |v| v / (NUMBER_OF_SIMULATIONS / 100.0) })
rescue => e
  #binding.pry
end

begin
  results = []
  if ARGV.include?('--help')
    puts <<~HELP
      Usage: ruby xg_script.rb [options] [HOME AWAY LINEUP_URL]

      Options:
        --help          Show this help message and exit
        --reset-index      Clear index.txt and delete all proposal CSVs, then continue
        --all-leagues      Fetch all leagues from WhoScored, ignoring AVAILABLE_LEAGUES filter
        --evaluate         Report accuracy across all archived proposals in proposals/
        --tips             After simulation, ask Claude for the best tips (requires `claude` CLI)
        --tips-only        Re-run Claude tips from existing CSVs without re-scraping
        --discover-fields       Print all WhoScored player summary JSON field names (use to audit available keys)
        --discover-team-html    Dump WhoScored team page HTML/scripts to identify corners/offsides selectors

      Positional arguments (optional):
        HOME            Home team name (runs a single match instead of today's fixtures)
        AWAY            Away team name
        LINEUP_URL      WhoScored lineups URL for the match
    HELP
    exit!
  end

  if ARGV.include?('--evaluate')
    puts evaluate_model
    exit!
  end

  if ARGV.include?('--tips-only')
    ask_claude_for_tips_from_csvs
    exit!
  end

  Selenium::WebDriver.logger.level = :error

  if ARGV.include?('--reset-index')
    File.write('index.txt', '')
    File.delete('bet_proposals.csv')        if File.exist?('bet_proposals.csv')
    File.delete('player_proposals.csv')     if File.exist?('player_proposals.csv')
    File.delete('ht_proposals.csv')         if File.exist?('ht_proposals.csv')
    File.delete('offsides_proposals.csv')   if File.exist?('offsides_proposals.csv')
    puts "index.txt and all proposal CSVs reset"
  end

  positional_args = ARGV.reject { |a| a.start_with?('--') || a =~ /^\d+$/ }

  if positional_args.count < 3
    ids = read_index_file

    date_str = Date.today.strftime("%Y%m%d")
    matches = games("https://www.whoscored.com/livescores/data?d=#{date_str}&isSummary=false")

    matches.each do |m|
      next if ids.include?(m[:id])
      next unless m[:url]

      puts "#{NAMES_MAP[m[:home]] || m[:home]} - #{NAMES_MAP[m[:away]] || m[:away]}"

      lineup = positional_args[2] || starting_eleven(m[:lineup_url])
      predicted = lineup.nil?
      lineup ||= predicted_eleven(m[:url])

      match_xgs = xgs_new(
        (NAMES_MAP[m[:home]] || m[:home]).split(' ').join('_'),
        (NAMES_MAP[m[:away]] || m[:away]).split(' ').join('_'),
        m[:home_id],
        m[:away_id],
        lineup,
        m[:tournament_id],
        predicted
      )
      #binding.pry
      next unless match_xgs

      sim = simulate_match(NAMES_MAP[m[:home]] || m[:home], NAMES_MAP[m[:away]] || m[:away], match_xgs)
      next unless sim

      if m[:bet1].to_f > 1 && m[:betx].to_f > 1 && m[:bet2].to_f > 1
        home_edge, home_kelly = market_edge_kelly(sim[:home], m[:bet1])
        draw_edge, draw_kelly = market_edge_kelly(sim[:draw], m[:betx])
        away_edge, away_kelly = market_edge_kelly(sim[:away], m[:bet2])
        sim.merge!(
          bet1: m[:bet1], betx: m[:betx], bet2: m[:bet2],
          home_edge: home_edge, draw_edge: draw_edge, away_edge: away_edge,
          home_kelly: home_kelly || 0, draw_kelly: draw_kelly || 0, away_kelly: away_kelly || 0
        )
      end

      # Edge/Kelly for additional markets (computed independently of 1/X/2 odds)
      {
        o15: [sim[:over15],          m[:bet_o15]],
        u15: [sim[:under15],         m[:bet_u15]],
        o25: [sim[:over25],          m[:bet_o25]],
        u25: [sim[:under25],         m[:bet_u25]],
        o35: [sim[:over35],          m[:bet_o35]],
        u35: [sim[:under35],         m[:bet_u35]],
        gg:  [sim[:gg],              m[:bet_gg]],
        ng:  [100.0 - sim[:gg],      m[:bet_ng]],
        ht1: [sim[:ht_home],         m[:bet_ht1]],
        htx: [sim[:ht_draw],         m[:bet_htx]],
        ht2: [sim[:ht_away],         m[:bet_ht2]]
      }.each do |mkt, (sim_pct, odds)|
        edge, kelly = market_edge_kelly(sim_pct, odds)
        sim[:"bet_#{mkt}"]   = odds.to_f > 1 ? odds : nil
        sim[:"#{mkt}_edge"]  = edge
        sim[:"#{mkt}_kelly"] = kelly || 0
      end

      results << sim
      write_to_index_file(m[:id])
    rescue => e
      next
    end

  else
    puts "#{positional_args[0]} - #{positional_args[1]}"
    stats = xgs_new(positional_args[0], positional_args[1], starting_eleven(positional_args[2]))
    simulate_match(positional_args[0], positional_args[1], stats)
  end
ensure
  export_to_csv(results)
  export_player_proposals_csv(results)
  export_ht_proposals_csv(results)
  export_offsides_csv(results)
  predicted_lineups = results.each_with_object({}) do |r, h|
    h["#{r[:home_team]}-#{r[:away_team]}"] = true if r[:predicted_lineup]
  end
  body = build_proposals(predicted_lineups)
  puts body unless body.empty?

  if ARGV.include?('--tips')
    tips = ask_claude_for_tips(results)
    body += tips if tips
  end

  if results.any?
    send_proposals_email(body) unless body.empty?
  end
end
