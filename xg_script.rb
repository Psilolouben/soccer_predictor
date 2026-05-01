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

NUMBER_OF_SIMULATIONS = 100_000

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
        bet_gg:  g.dig('bets', 'gg',      'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f,
        bet_ng:  g.dig('bets', 'ng',      'offers')&.first{|m| m['bettingProvider'] == 'B3'}&.dig('oddsDecimal')&.to_f
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

  home_cards = starting_eleven[:home].each_with_object({}) do |p, hsh|
    yellow = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}&.first.try(:[], 'yellowCard') || 0
    red = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}&.first.try(:[], 'redCard') || 0
    apps = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}&.first.try(:[], 'apps') || 0
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

  away_cards = starting_eleven[:away].each_with_object({}) do |p, hsh|
    yellow = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}&.first.try(:[], 'yellowCard') || 0
    red = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}&.first.try(:[], 'redCard') || 0
    apps = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['name'].include?(p) && x['tournamentId'].to_i == competition_id.to_i}&.first.try(:[], 'apps') || 0
    hsh[p] = apps.zero? ? 0 : ((yellow + red) / apps.to_f)
  end
  sleep(1)

  stats = {
    home_xgs: home_xgs,
    away_xgs: away_xgs,
    xgs_warning: xgs_warning,
    home_cards: home_cards,
    away_cards: away_cards,
    predicted_lineup: predicted_lineup
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

def export_to_csv(proposals)
  headers = ['Home', 'Away', '1', 'X', '2', '1X', 'X2', '12', 'O15', 'U15', 'O25', 'U25', 'O35', 'U35', 'GG', 'Missing XGS', 'Both Cards', 'Score',
             'Bet1', 'BetX', 'Bet2', 'BetO15', 'BetU15', 'BetO25', 'BetU25', 'BetO35', 'BetU35', 'BetGG', 'BetNG',
             'Edge1', 'EdgeX', 'Edge2', 'EdgeO15', 'EdgeU15', 'EdgeO25', 'EdgeU25', 'EdgeO35', 'EdgeU35', 'EdgeGG', 'EdgeNG',
             'Kelly1', 'KellyX', 'Kelly2', 'KellyO15', 'KellyU15', 'KellyO25', 'KellyU25', 'KellyO35', 'KellyU35', 'KellyGG', 'KellyNG']
  CSV.open("bet_proposals.csv", "a", :write_headers=> (!File.exist?("bet_proposals.csv") || !CSV.read("bet_proposals.csv", headers: true).headers == headers),
                                     :headers => headers, col_sep: ';') do |csv|
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
  end;0
end

def read_index_file
  File.readlines('index.txt', chomp: true).map(&:to_i)
end

def import_from_csv
  CSV.read("bet_proposals.csv", headers: true, col_sep: ';').map(&:to_h)
end

def build_proposals(predicted_lineups = {})
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

    # Edge-based exceptional bucket: any market where the bookmaker misprices by
    # more than EDGE_EXCEPTION_THRESHOLD regardless of raw probability threshold.
    # 'NG' has no sim column — its probability is derived as 100 - GG.
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

    next if bets.empty?

    { g: g, bets: bets }
  end

  return '' if rows.empty?

  sep = '─' * 56
  lines = []
  rows.each do |row|
    g, bets = row[:g], row[:bets]

    score_part, pct_part = g['Score'].to_s.split(':')
    score_str = pct_part ? "#{score_part} (#{pct_part.to_f.round(1)}%)" : ''

    odds = [g['Bet1'].to_f, g['BetX'].to_f, g['Bet2'].to_f]
    odds_str = odds.map { |o| o > 0 ? format('%.2f', o) : '-' }.join(' / ')

    lines << sep
    match_key = "#{g['Home']}-#{g['Away']}"
    header = "#{g['Home']} vs #{g['Away']}"
    header += '  [PREDICTED XI]' if predicted_lineups[match_key]
    lines << "#{header.ljust(38)}  #{score_str}"
    lines << "  Odds: #{odds_str}"
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
  end
  lines << sep
  lines.join("\n")
end

def print_proposals(predicted_lineups = {})
  body = build_proposals(predicted_lineups)
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

GMAIL_ADDRESS = 'marky.rigas@gmail.com'.freeze

def send_proposals_email(body)
  password = ENV['GMAIL_APP_PASSWORD']
  unless password
    puts "GMAIL_APP_PASSWORD env var not set — skipping email"
    return
  end

  date_str = Date.today.strftime('%Y-%m-%d')
  message = <<~MSG
    From: Soccer Predictor <#{GMAIL_ADDRESS}>
    To: #{GMAIL_ADDRESS}
    Subject: Bet proposals #{date_str}
    Content-Type: text/plain; charset=UTF-8

    #{body}
  MSG

  smtp = Net::SMTP.new('smtp.gmail.com', 587)
  smtp.enable_starttls
  smtp.start('localhost', GMAIL_ADDRESS, password, :login) do |s|
    s.send_message(message, GMAIL_ADDRESS, GMAIL_ADDRESS)
  end
  puts "Email sent to #{GMAIL_ADDRESS}"
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
    score: ''
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
  res[:score] = scores.tally.transform_values{|v| v/(NUMBER_OF_SIMULATIONS.to_f / 100)}.sort_by{|_, v| v}.reverse.first.join(':')

  return res.merge(res.except(:home_team, :away_team, :missing_xgs, :predicted_lineup, :home_scorers, :away_scorers, :score).transform_values{ |v| v / (NUMBER_OF_SIMULATIONS / 100.0) })
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
        --reset-index   Clear index.txt and delete bet_proposals.csv, then continue
        --all-leagues   Fetch all leagues from WhoScored, ignoring AVAILABLE_LEAGUES filter

      Positional arguments (optional):
        HOME            Home team name (runs a single match instead of today's fixtures)
        AWAY            Away team name
        LINEUP_URL      WhoScored lineups URL for the match
    HELP
    exit!
  end

  Selenium::WebDriver.logger.level = :error

  if ARGV.include?('--reset-index')
    File.write('index.txt', '')
    File.delete('bet_proposals.csv') if File.exist?('bet_proposals.csv')
    puts "index.txt and bet_proposals.csv reset"
  end

  if ARGV.count < 3
    ids = read_index_file

    date_str = Date.today.strftime("%Y%m%d")
    matches = games("https://www.whoscored.com/livescores/data?d=#{date_str}&isSummary=false")

    matches.each do |m|
      next if ids.include?(m[:id])
      next unless m[:url]

      puts "#{NAMES_MAP[m[:home]] || m[:home]} - #{NAMES_MAP[m[:away]] || m[:away]}"

      lineup = ARGV[2] || starting_eleven(m[:lineup_url])
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
        ng:  [100.0 - sim[:gg],      m[:bet_ng]]
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
    puts "#{ARGV[0]} - #{ARGV[1]}"
    stats = xgs(ARGV[0], ARGV[1], starting_eleven(ARGV[2]))
    simulate_match(ARGV[0], ARGV[1], stats)
  end
ensure
  export_to_csv(results)
  predicted_lineups = results.each_with_object({}) do |r, h|
    h["#{r[:home_team]}-#{r[:away_team]}"] = true if r[:predicted_lineup]
  end
  print_proposals(predicted_lineups)
  if results.any?
    body = build_proposals(predicted_lineups)
    send_proposals_email(body) unless body.empty?
  end
end
