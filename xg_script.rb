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

AVAILABLE_LEAGUES = ['France-Ligue-1', 'England-Premier-League', 'Spain-LaLiga', 'Germany-Bundesliga', 'Italy-Serie-A', 'Europe-Champions-League', 'Europa League']
#AVAILABLE_LEAGUES = ['England-Premier-League', 'Spain-LaLiga', 'Germany-Bundesliga']

def games(url)
  br = Watir::Browser.new
  br.goto(url)
  a = JSON.parse(br.elements.first.text)['tournaments'].
    select { |x| AVAILABLE_LEAGUES.include?(x['tournamentName']) }.
    map { |x| x['matches'].map do |g|
      {
        home: g['homeTeamName'],
        home_id: g['homeTeamId'],
        away: g['awayTeamName'],
        away_id: g['awayTeamId'],
        url: "https://www.whoscored.com/Matches/#{g['id']}/Preview/"
      }
    end
  }.flatten
  br.quit
  a
end

def starting_eleven(url)
  br = Watir::Browser.new
  br.goto(url)
  br.elements(class: 'player-name player-link cnt-oflow rc').wait_until(timeout: 60) do |p|
    p.all?{ |x| !x.inner_html.empty? }
  end

  a = {
    home: br.elements(class: 'player-name player-link cnt-oflow rc').map(&:inner_html).take(11),
    away: br.elements(class: 'player-name player-link cnt-oflow rc').map(&:inner_html).reverse.take(11)
  }
  br.close
  a
end

def goal_and_assist(goal, assist)
  (goal + assist - (goal * assist)) * 100
end

def xgs(home_team, away_team, home_id, away_id, starting_eleven)
  resp = HTTParty.get("https://understat.com/team/#{home_team}/2024", timeout: 60)
  return if Nokogiri::HTML(resp.body).xpath("//title").text.include?('404')

  home_data_json = Nokogiri::HTML(resp.body).xpath("//script")[3].children.first.text.split("JSON.parse(\'")[1].split("\'").first
  home_data = JSON.parse("\"#{home_data_json}\"".undump)

  home_team_data_json = Nokogiri::HTML(resp.body).xpath("//script")[2].children.first.text.split("JSON.parse(\'")[1].split("\'").first
  home_team_data = JSON.parse("\"#{home_team_data_json}\"".undump)
  home_team_xga = home_team_data['situation'].sum{|_, v| v['against']['xG']} / home_data.map{|x| x['games']}.max.to_f

  home_players = home_data.each_with_object({}) do |x, arr|
    arr[x['id']] = { name: x['player_name'], xg: (x['xG'].to_f / (x['time'].to_f / 90)), xa: (x['xA'].to_f / (x['time'].to_f / 90)), yc: (x['yellow_cards'].to_i / (x['time'].to_f / 90))}
  end

  return if home_players.empty?
  #home_team_data_json = Nokogiri::HTML(resp).xpath("//script")[2].children.first.text.split("JSON.parse(\'")[1].split("\'").first
  #home_team_data = JSON.parse("\"#{home_team_data_json}\"".undump)
  #home_team_GA = home_team_data['situation'].sum{|_, v| v['against']['xG']}
  #home_team_games = home_team_data['situation'].sum{|_, v| v['against']['xG']}
  #binding.pry

  hp = starting_eleven[:home].map do |h|
    proposal = home_players.select{ |_, hm| I18n.transliterate(hm[:name]).include?(I18n.transliterate(h)) }.keys
    if proposal.empty? || proposal.count > 1
      puts "No xg found for #{h}"
      puts home_players.sort_by{|_, v| v[:name].split(' ').last}.map{|k,v| { k => v.slice(:name)}}
      puts "Please input id for #{h}"
      proposal = $stdin.gets.chomp
    end
    proposal
  end.flatten

  resp = HTTParty.get("https://understat.com/team/#{away_team}/2024", timeout: 60)
  return if Nokogiri::HTML(resp.body).xpath("//title").text.include?('404')

  away_data_json = Nokogiri::HTML(resp.body).xpath("//script")[3].children.first.text.split("JSON.parse(\'")[1].split("\'").first
  away_data = JSON.parse("\"#{away_data_json}\"".undump)

  away_team_data_json = Nokogiri::HTML(resp.body).xpath("//script")[2].children.first.text.split("JSON.parse(\'")[1].split("\'").first
  away_team_data = JSON.parse("\"#{away_team_data_json}\"".undump)
  away_team_xga = away_team_data['situation'].sum{|_, v| v['against']['xG']} / away_data.map{|x| x['games']}.max.to_f

  away_players = away_data.each_with_object({}) do |x, arr|
    arr[x['id']] = { name: x['player_name'], xg: (x['xG'].to_f / (x['time'].to_f / 90)), xa: (x['xA'].to_f / (x['time'].to_f / 90)), yc: (x['yellow_cards'].to_i / (x['time'].to_f / 90))}
  end

  ap = starting_eleven[:away].map do |a|
    proposal = away_players.select{ |_, am| I18n.transliterate(am[:name]).include?(I18n.transliterate(a)) }.keys

    if proposal.empty? || proposal.count > 1
      puts "No xg found for #{a}"
      puts away_players.sort_by{|_, v| v[:name].split(' ').last}.map{|k,v| { k => v.slice(:name)}}
      puts "Please input id for #{a}"
      proposal = $stdin.gets.chomp
    end
    proposal
  end.flatten

  stats = {
    home_xgs: {},
    away_xgs: {},
    home_xas: {},
    away_xas: {},
    home_cards: {},
    away_cards: {},
    home_xga: home_team_xga,
    away_xga: away_team_xga
  }

  hp.map(&:strip).each{ |i| stats[:home_xgs][home_players[i][:name]] = home_players[i][:xg].to_f }
  ap.map(&:strip).each{ |i| stats[:away_xgs][away_players[i][:name]] = away_players[i][:xg].to_f }
  hp.map(&:strip).each{ |i| stats[:home_xas][home_players[i][:name]] = home_players[i][:xa].to_f }
  ap.map(&:strip).each{ |i| stats[:away_xas][away_players[i][:name]] = away_players[i][:xa].to_f }
  hp.map(&:strip).each{ |i| stats[:home_cards][home_players[i][:name]] = home_players[i][:yc].to_f }
  ap.map(&:strip).each{ |i| stats[:away_cards][away_players[i][:name]] = away_players[i][:yc].to_f }

  stats
end

def xgs_new(home_team, away_team, home_id, away_id, starting_eleven)
  home_url = "https://www.whoscored.com/StatisticsFeed/1/GetPlayerStatistics?category=xg-stats&subcategory=summary&statsAccumulationType=0&isCurrent=true&playerId=&teamIds=#{home_id}&sortBy=xg&sortAscending=false&field=Overall&isMinApp=false&page=&includeZeroValues=true&numberOfPlayersToPick=&incPens=true"
  away_url = "https://www.whoscored.com/StatisticsFeed/1/GetPlayerStatistics?category=xg-stats&subcategory=summary&statsAccumulationType=0&isCurrent=true&playerId=&teamIds=#{away_id}&sortBy=xg&sortAscending=false&field=Overall&isMinApp=false&page=&includeZeroValues=true&numberOfPlayersToPick=&incPens=true"
  home_team_url = "https://www.whoscored.com/StatisticsFeed/1/GetTeamStatistics?category=summaryteam&subcategory=all&statsAccumulationType=0&field=Overall&tournamentOptions=&timeOfTheGameStart=&timeOfTheGameEnd=&teamIds=#{home_id}"
  away_team_url = "https://www.whoscored.com/StatisticsFeed/1/GetTeamStatistics?category=xg-teamstats&subcategory=summary&statsAccumulationType=0&field=Overall&tournamentOptions=&timeOfTheGameStart=&timeOfTheGameEnd=&teamIds=#{away_id}&stageId=&sortBy=xG&sortAscending=false&page=&numberOfTeamsToPick=&isCurrent=true&formation=&incPens=true&against=false"

  br = Watir::Browser.new
  br.goto(home_url)

  cookies = br.cookies.to_a  # Export all cookies

  # Save cookies to a file (optional, for preserving between sessions)
  File.open('cookies.json', 'w') do |f|
    f.write(cookies.to_json)
  end

  home_xgs = starting_eleven[:home].each_with_object({}) do |p, hsh|
    hsh[p] = JSON.parse(br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p)}&.first.try(:[], 'xGPerNinety') || 0
  end

  br.goto(away_url)
  away_xgs = starting_eleven[:away].each_with_object({}) do |p, hsh|
    hsh[p] = JSON.parse(br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p)}&.first.try(:[], 'xGPerNinety') || 0
  end

  br.quit

  br = Watir::Browser.new
  br.goto(home_team_url)
  binding.pry
  away_xgs = starting_eleven[:away].each_with_object({}) do |p, hsh|
    hsh[p] = JSON.parse(br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p)}&.first.try(:[], 'xGPerNinety') || 0
  end

  br.goto(away_team_url)
  away_xgs = starting_eleven[:away].each_with_object({}) do |p, hsh|
    hsh[p] = JSON.parse(br.elements.first.text)['playerTableStats'].select{|x| x['lastName'].include?(p)}&.first.try(:[], 'xGPerNinety') || 0
  end

  stats = {
    home_xgs: home_xgs,
    away_xgs: away_xgs,
    home_xga: home_team_xga,
    away_xga: away_team_xga
  }

  stats
end

def write_to_file(res)
  open("res_#{Date.today}.txt", 'a') { |f|
  f.puts res
}
end

def simulate_match(home_team, away_team, stats)
  res = {
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
    home_assist_stats = stats[:home_xas].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    away_assist_stats = stats[:away_xas].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    home_yellow_cards = stats[:home_cards].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}
    away_yellow_cards = stats[:away_cards].transform_values { |x| Distribution::Poisson.rng(x) }.select{|_, v| v > 0}

    home_xga = Distribution::Poisson.rng(stats[:home_xga]).to_i
    away_xga = Distribution::Poisson.rng(stats[:away_xga]).to_i

    home = [home_xg_stats.sum{ |_, v| v }, away_xga].min
    away = [away_xg_stats.sum{ |_, v| v }, home_xga].min

    home_scorers << home_xg_stats.keys
    away_scorers << away_xg_stats.keys
    home_assists << home_assist_stats.keys
    away_assists << away_assist_stats.keys

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

  res.transform_values!{ |v| v / (NUMBER_OF_SIMULATIONS / 100.0) }
  write_to_file "#{home_team} - #{away_team}"
  write_to_file res
  write_to_file '----------------------------------------------------------'
  write_to_file 'GOALS'
  write_to_file (home_scorers.flatten.tally.transform_values{|x| x/(NUMBER_OF_SIMULATIONS / 100.0)}.sort_by{|_,v| v}.reverse.take(5).to_h)
  write_to_file (away_scorers.flatten.tally.transform_values{|x| x/(NUMBER_OF_SIMULATIONS / 100.0)}.sort_by{|_,v| v}.reverse.take(5).to_h)
  write_to_file '----------------------------------------------------------'
  write_to_file 'ASSISTS'
  write_to_file (home_assists.flatten.tally.transform_values{|x| x/(NUMBER_OF_SIMULATIONS / 100.0)}.sort_by{|_,v| v}.reverse.take(5).to_h)
  write_to_file (away_assists.flatten.tally.transform_values{|x| x/(NUMBER_OF_SIMULATIONS / 100.0)}.sort_by{|_,v| v}.reverse.take(5).to_h)
  write_to_file '----------------------------------------------------------'
  write_to_file 'GOALS AND ASSISTS'
  home_candidates = home_scorers.flatten.tally.transform_values{|x| x/(NUMBER_OF_SIMULATIONS / 100.0)}.merge(home_assists.flatten.tally.transform_values{|x| x/(NUMBER_OF_SIMULATIONS / 100.0)}).keys
  away_candidates = away_scorers.flatten.tally.transform_values{|x| x/(NUMBER_OF_SIMULATIONS / 100.0)}.merge(away_assists.flatten.tally.transform_values{|x| x/(NUMBER_OF_SIMULATIONS / 100.0)}).keys
  write_to_file (
    home_candidates.map do |x|
      {
        x => goal_and_assist(
          home_scorers.flatten.tally.transform_values{|xi| xi/NUMBER_OF_SIMULATIONS.to_f}[x] || 0,
          home_assists.flatten.tally.transform_values{|xi| xi/NUMBER_OF_SIMULATIONS.to_f}[x] || 0
        )
      }
    end.sort_by{|v| v.values}.reverse.take(5))
  write_to_file (
    away_candidates.map do |x|
      {
        x => goal_and_assist(
          away_scorers.flatten.tally.transform_values{|xi| xi/NUMBER_OF_SIMULATIONS.to_f}[x] || 0,
          away_assists.flatten.tally.transform_values{|xi| xi/NUMBER_OF_SIMULATIONS.to_f}[x] || 0
        )
      }
    end.sort_by{|v| v.values}.reverse.take(5))
  write_to_file '----------------------------------------------------------'
  write_to_file 'SCORES'
  write_to_file (scores.tally.transform_values{|x| x/(NUMBER_OF_SIMULATIONS / 100.0)}.sort_by{|_,v| v}.reverse.take(8))
  write_to_file '----------------------------------------------------------'
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
      #x['over_corners'].values.any? { |r| r > (100 - CORNER_THRESHOLD) } ||
      #x['over_corners'].values.any? { |r| r < (CORNER_THRESHOLD) } ||
      (x['over_05_penalties'] > PENALTY_THRESHOLD) ||
      (x['over_05_red_cards'] > RED_CARD_THRESHOLD) ||
      x[:home_players].any? { |r| r.values.first[:goals] > (SCORER_THRESHOLD) ||  r.values.first[:assists] > (SCORER_THRESHOLD)} ||
      x[:away_players].any? { |r| r.values.first[:goals] > (SCORER_THRESHOLD) ||  r.values.first[:assists] > (SCORER_THRESHOLD)} ||
      (x[:home_card][:yes] > 85) && (x[:away_card][:yes] > 85)
  end
end

if ARGV.count < 3
  date_str = Date.today.strftime("%Y%m%d")
  matches = games("https://www.whoscored.com/livescores/data?d=#{date_str}&isSummary=true")
  matches.each do |m|
    next unless m[:url]
    puts "#{NAMES_MAP[m[:home]] || m[:home]} - #{NAMES_MAP[m[:away]] || m[:away]}"
    match_xgs = xgs(
      (NAMES_MAP[m[:home]] || m[:home]).split(' ').join('_'), (NAMES_MAP[m[:away]] || m[:away]).split(' ').join('_'), m[:home_id], m[:away_id], ARGV[2] || starting_eleven( m[:url])
    )
    next unless match_xgs
    simulate_match(NAMES_MAP[m[:home]] || m[:home], NAMES_MAP[m[:away]] || m[:away], match_xgs)
  end
else
  puts "#{ARGV[0]} - #{ARGV[1]}"
  stats = xgs(ARGV[0], ARGV[1], starting_eleven(ARGV[2]))
  simulate_match(ARGV[0], ARGV[1], stats)
end
