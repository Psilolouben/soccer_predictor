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
  @br = Watir::Browser.new
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
