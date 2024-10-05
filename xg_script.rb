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

UNDER_OVER_HALF_THRESHOLD = 80
SINGLE_THRESHOLD = 60
DRAW_THRESHOLD = 35
DOUBLE_THRESHOLD = 75
UNDER_OVER_THRESHOLD = 70
CORNER_THRESHOLD = 20
CARDS_THRESHOLD = 20
PENALTY_THRESHOLD = 40
RED_CARD_THRESHOLD = 40
SCORER_THRESHOLD = 40

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
                     'Europe-Champions-League', 'Europa League',
                     'Championship', 'Premiership', 'Liga Portugal',
                     'Premier League', 'Super Lig', 'Eredivisie']

def games(url)
  @br.goto(url)
  a = JSON.parse(@br.elements.first.text)['tournaments'].
    select { |x| AVAILABLE_LEAGUES.include?(x['tournamentName']) }.
    map { |x| x['matches'].map do |g|
      {
        id: g['id'],
        home: g['homeTeamName'],
        home_id: g['homeTeamId'],
        away: g['awayTeamName'],
        away_id: g['awayTeamId'],
        url: "https://www.whoscored.com/Matches/#{g['id']}/Preview/"
      }
    end
  }.flatten
  a
end

def starting_eleven(url)
  @br.goto(url)
  @br.elements(class: 'player-name player-link cnt-oflow rc').wait_until(timeout: 60) do |p|
    p.all?{ |x| !x.inner_html.empty? }
  end

  a = {
    home: @br.elements(class: 'player-name player-link cnt-oflow rc').map(&:inner_html).take(11),
    away: @br.elements(class: 'player-name player-link cnt-oflow rc').map(&:inner_html).reverse.take(11)
  }
  a
end

def goal_and_assist(goal, assist)
  (goal + assist - (goal * assist)) * 100
end

def xgs_new(home_team, away_team, home_id, away_id, starting_eleven)
  home_url = "https://www.whoscored.com/StatisticsFeed/1/GetPlayerStatistics?category=xg-stats&subcategory=summary&statsAccumulationType=0&isCurrent=true&playerId=&teamIds=#{home_id}&sortBy=xg&sortAscending=false&field=Overall&isMinApp=false&page=&includeZeroValues=true&numberOfPlayersToPick=&incPens=true"
  away_url = "https://www.whoscored.com/StatisticsFeed/1/GetPlayerStatistics?category=xg-stats&subcategory=summary&statsAccumulationType=0&isCurrent=true&playerId=&teamIds=#{away_id}&sortBy=xg&sortAscending=false&field=Overall&isMinApp=false&page=&includeZeroValues=true&numberOfPlayersToPick=&incPens=true"
  home_team_url = "https://www.whoscored.com/Teams/#{home_id}/Show"
  away_team_url = "https://www.whoscored.com/Teams/#{away_id}/Show"
  @br.goto(home_url)

  xgs_warning = false
  home_xgs = starting_eleven[:home].each_with_object({}) do |p, hsh|
    hsh[p] = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p)}&.first.try(:[], 'xGPerNinety') || 0
  end

  xgs_warning = true if home_xgs.count{ |_,v| v.to_i == 0} < 9

  @br.goto(away_url)
  away_xgs = starting_eleven[:away].each_with_object({}) do |p, hsh|
    hsh[p] = JSON.parse(@br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p)}&.first.try(:[], 'xGPerNinety') || 0
  end

  xgs_warning = true if away_xgs.count{ |_,v| v.to_i == 0} < 9

  @br.goto(home_team_url)
  if @br.button(text: "AGREE").exists?
    @br.button(text: "AGREE").click
  elsif @br.a(text: "AGREE").exists?
    @br.a(text: "AGREE").click
  end

  @br.a(text: "xG").click
  @br.a(text: "Against").click
  @br.wait_until(timeout: 60) { @br.div(id: 'statistics-team-table-xg').exists? }
  @br.wait_until(timeout: 60) { @br.div(id: 'statistics-team-table-xg').trs.length > 1 }
  home_team_xga = @br.div(id: 'statistics-team-table-xg').divs.first.tables.first.tbodys.first.trs.first.tds[2].text.to_f / @br.div(id: 'statistics-team-table-xg').divs.first.tables.first.tbodys.first.trs.first.tds[1].text.to_f

  sleep(5)

  @br.goto(away_team_url)
  @br.a(text: "xG").click
  @br.a(text: "Against").click
  @br.wait_until(timeout: 60) { @br.div(id: 'statistics-team-table-xg').exists? }
  @br.wait_until(timeout: 60) { @br.div(id: 'statistics-team-table-xg').trs.length > 1 }
  away_team_xga = @br.div(id: 'statistics-team-table-xg').divs.first.tables.first.tbodys.first.trs.first.tds[2].text.to_f / @br.div(id: 'statistics-team-table-xg').divs.first.tables.first.tbodys.first.trs.first.tds[1].text.to_f

  stats = {
    home_xgs: home_xgs,
    away_xgs: away_xgs,
    xgs_warning: xgs_warning,
    home_xga: home_team_xga,
    away_xga: away_team_xga
  }
  stats
end

def write_to_index_file(res)
  open("index.txt", 'a') { |f|
  f.puts res
}
end

def export_to_csv(proposals)
  headers = ['Home', 'Away', '1X', 'X2', '12', 'O15', 'U15', 'O25', 'U25', 'O35', 'U35', 'GG', 'Missing XGS']
  CSV.open("bet_proposals.csv", "a", :write_headers=> (!File.exist?("bet_proposals.csv") || !CSV.read("bet_proposals.csv", headers: true).headers == headers),
                                     :headers => headers, col_sep: ';') do |csv|
    proposals.each do |game|
      puts game if game.except(:home_team, :away_team, :missing_xgs).values.any?{|v| v.to_i > 80}
      csv << [game[:home_team], game[:away_team], game[:home] + game[:draw], game[:draw] + game[:away], game[:home] + game[:away], game[:over15], game[:under15], game[:over25], game[:under25], game[:over35], game[:under35], game[:gg], game[:missing_xgs]]
    end
  end;0
end

def read_index_file
  File.readlines('index.txt', chomp: true).map(&:to_i)
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
    both_cards: 0
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
    #home_yellow_cards = stats[:home_cards].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    #away_yellow_cards = stats[:away_cards].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}

    home_xga = Distribution::Poisson.rng(stats[:home_xga]).to_i
    away_xga = Distribution::Poisson.rng(stats[:away_xga]).to_i

    home = [home_xg_stats.sum{ |_, v| v }, home_xga].min
    away = [away_xg_stats.sum{ |_, v| v }, away_xga].min

    home_scorers << home_xg_stats.keys
    away_scorers << away_xg_stats.keys
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

    #home_yellow = home_yellow_cards.sum{ |_, v| v }
    #away_yellow = away_yellow_cards.sum{ |_, v| v }

    #if home_yellow > 0 && away_yellow > 0
    #  res[:both_cards] += 1
    #end
  end

  return res.merge(res.except(:home_team, :away_team, :missing_xgs).transform_values{ |v| v / (NUMBER_OF_SIMULATIONS / 100.0) })
end

def above_threshold(matches)
  matches.reject(&:empty?).select do |x|
    x = x.with_indifferent_access
    [x['home_win_perc'], x['away_win_perc'], x['draw_perc']].any? { |r| r > SINGLE_THRESHOLD } ||
      (x['draw_perc'] > DRAW_THRESHOLD) ||
      [x[:home_win_perc] + x[:away_win_perc], x[:home_win_perc] + x[:draw_perc], x[:away_win_perc] + x[:draw_perc]].any? { |r| r > DOUBLE_THRESHOLD } ||
      x['under_goals'].values.any? { |v| v > UNDER_OVER_THRESHOLD } ||
      x['over_goals'].values.any? { |v| v > UNDER_OVER_THRESHOLD } ||
      (x['under_perc'] > UNDER_OVER_THRESHOLD) ||
      (x['goal_goal'] > UNDER_OVER_THRESHOLD) ||
      (x['no_goal_goal'] > UNDER_OVER_THRESHOLD) ||
      [x['over_goals_half']['05'], x['over_goals_half']['15']].any? { |r| r > (UNDER_OVER_HALF_THRESHOLD) } ||
      [x['over_goals_half']['05'], x['over_goals_half']['15']].any? { |r| r < (100 - UNDER_OVER_HALF_THRESHOLD) } ||
      [x['over_cards']['3.5'], x['over_cards']['4.5'], x['over_cards']['5.5']].any? { |r| r > (100 - CARDS_THRESHOLD) } ||
      [x['over_cards']['3.5'], x['over_cards']['4.5'], x['over_cards']['5.5']].any? { |r| r < (CARDS_THRESHOLD) } ||
      (x['over_05_penalties'] > PENALTY_THRESHOLD) ||
      (x['over_05_red_cards'] > RED_CARD_THRESHOLD) ||
      x[:home_players].any? { |r| r.values.first[:goals] > (SCORER_THRESHOLD) ||  r.values.first[:assists] > (SCORER_THRESHOLD)} ||
      x[:away_players].any? { |r| r.values.first[:goals] > (SCORER_THRESHOLD) ||  r.values.first[:assists] > (SCORER_THRESHOLD)} ||
      (x[:home_card][:yes] > 85) && (x[:away_card][:yes] > 85)
  end
end

begin
  results = []
  if ARGV.count < 3
    ids = read_index_file
    @br = Watir::Browser.new
    date_str = Date.today.strftime("%Y%m%d")
    matches = games("https://www.whoscored.com/livescores/data?d=#{date_str}&isSummary=true")

    matches.each do |m|
      next if ids.include?(m[:id])
      next unless m[:url]

      puts "#{NAMES_MAP[m[:home]] || m[:home]} - #{NAMES_MAP[m[:away]] || m[:away]}"
      match_xgs = xgs_new(
        (NAMES_MAP[m[:home]] || m[:home]).split(' ').join('_'),
        (NAMES_MAP[m[:away]] || m[:away]).split(' ').join('_'),
        m[:home_id], m[:away_id], ARGV[2] || starting_eleven( m[:url])
      )
      next unless match_xgs

      results << simulate_match(NAMES_MAP[m[:home]] || m[:home], NAMES_MAP[m[:away]] || m[:away], match_xgs)
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
  @br.quit
end
