require 'httparty'

class Fetcher
  FIXTURES_URL = 'http://apiv2.apifootball.com/?action=get_events'.freeze
  HEAD2HEAD_URL = 'http://apiv2.apifootball.com/?action=get_H2H'.freeze
  ODDS_URL = 'https://apiv2.apifootball.com/?action=get_odds'.freeze


  LEAGUES = {
    primera: '468',
    la_liga2: '469',
    superleague: '209',
    premier: '148',
    championship: '149',
    league_one: '150',
    league_two: '151',
    bundesliga: '195',
    ligue_1: '176',
    ligue_2: '177',
    eredivisie: '343',
    serie_a: '262',
    serie_b: '263',
    chl: '589',
    europa: '590',
    brazil_1: '68',
    primeira_liga: '391',
    jupiter_league: '51',
    premier_scotland: '423',
    super_league_swiss: '491',
    super_lig_turkey: '511'
  }.freeze

  attr_reader :params, :league_id

  # from_date, to_date, league_id, api_key
  # f = Fetcher.new(params: {from_date: Date.today.to_s, to_date: Date.tomorrow.to_s, league_id: '149'})
  def initialize(params: {})
    @params = params
    @league_id = params[:league_id]
  end

  def proposals(threshold = nil, games_back = 5)
    games = []

    leagues = league_id.blank? ? LEAGUES : LEAGUES.select{ |k,v| v== league_id }

    leagues.each do |key, value|
      puts "Scanning #{key}..."
      @league_id = value.to_s
      games << simulate(goals_per_game(games_back), games_back)
    end
    final_games = games.flatten

    if threshold.present?
      final_games = above_threshold(final_games, threshold)
    end

    final_games
  end

  def fixtures
    query = {
      'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad',
      'league_id' => @league_id,
      'from' => params[:from_date],
      'to' => params[:to_date]
    }
    response= JSON::parse(HTTParty.get(FIXTURES_URL, query: query).body.presence || '{}')

    return response if response.is_a?(Hash)

    response.select{|x| Time.parse(x['match_time']) > Time.now}
  end

  def simulate_league(games_back = 10)
    simulate(goals_per_game(games_back), games_back)
  end

  private

  def head_to_head(home, away)
    query = {
      'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad',
      'firstTeam' => home,
      'secondTeam' => away,
    }
    JSON::parse(HTTParty.get(HEAD2HEAD_URL, query: query).body.presence || '{}')
  end

  def self.get_leagues
    LEAGUES.keys
  end

  def goals_per_game(games_back = 8)
    estimations = []

    current_fixtures = fixtures

    return {} if current_fixtures.is_a?(Hash) && current_fixtures.key?('error')

    puts "#{current_fixtures.count} fixtures found"
    puts "Retrieving Match History for #{games_back} games back..."

    current_fixtures.each_with_index do |match, i|
      total_goals_away = 0
      total_goals_home = 0
      sleep(1)
      puts "#{i+1}/#{current_fixtures.count} #{match['match_hometeam_name']} - #{match['match_awayteam_name']}"

      h2h = head_to_head(match['match_hometeam_name'], match['match_awayteam_name'])
      next if h2h.empty?

      #head_to_head_results = h2h['firstTeam_VS_secondTeam'].take(games_back)
      home_team_last_results = h2h['firstTeam_lastResults'].take(games_back)
      away_team_last_results = h2h['secondTeam_lastResults'].take(games_back)

      home_team_last_results.each do |htr|
        if htr['match_hometeam_name'] == match['match_hometeam_name']
          total_goals_home += htr['match_hometeam_score'].to_i
        else
          total_goals_home += htr['match_awayteam_score'].to_i
        end
      end

      away_team_last_results.each do |htr|
        if htr['match_awayteam_name'] == match['match_awayteam_name']
          total_goals_away += htr['match_awayteam_score'].to_i
        else
          total_goals_away += htr['match_hometeam_score'].to_i
        end
      end

      estimations << {
        match_id: match['match_id'],
        home_team: match['match_hometeam_name'],
        away_team: match['match_awayteam_name'],
        home_goals_per_match:  total_goals_home / home_team_last_results.count.to_f,
        away_goals_per_match:  total_goals_away / away_team_last_results.count.to_f
      }
    end

    estimations
  end

  def simulate(games, games_back = 10, number_of_simulations = 100000)
    return {} if games.blank?

    puts "Simulating games for #{games_back} games back. Running #{number_of_simulations} times..."
    proposals = []

    games.each do |game|
      simulated_scores = []
      number_of_simulations.times do
        rand_home = rand * 2
        rand_away = rand * 2

        simulated_scores << {
          match_id: game[:match_id],
          home_team: game[:home_team],
          away_team: game[:away_team],
          home: (rand_home * game[:home_goals_per_match]).round,
          away: (rand_away * game[:away_goals_per_match]).round
        }
      end

      proposals <<
      {
        match_id: game[:match_id],
        home_team: game[:home_team],
        away_team: game[:away_team],
        home_win_perc: simulated_scores.select{|sc| sc[:home] > sc[:away]}.count * 100 / number_of_simulations.to_f,
        away_win_perc: simulated_scores.select{|sc| sc[:home] < sc[:away]}.count * 100 / number_of_simulations.to_f,
        draw_perc: simulated_scores.select{|sc| sc[:home] == sc[:away]}.count * 100 / number_of_simulations.to_f,
        under_perc: simulated_scores.select{|sc| sc[:home] + sc[:away] < 2.5}.count * 100 / number_of_simulations.to_f,
        over_perc: simulated_scores.select{|sc| sc[:home] + sc[:away] > 2.5}.count * 100 / number_of_simulations.to_f,
        goal_goal: simulated_scores.select{|sc| sc[:home] > 0 && sc[:away] > 0}.count * 100 / number_of_simulations.to_f
      }
    end

    proposals
  end



  def above_threshold(matches, threshold)
    filtered = matches.select{|x| x.except(:match_id, :home_team, :away_team).values.any?{|v| v >= threshold }}
    pp_proposals(filtered, threshold);0
  end

  def pp_proposals(games, threshold)
    games.each do |x|
      txt = "#{x[:home_team]} - #{x[:away_team]} "
      txt += "1 " if x[:home_win_perc] >= threshold
      txt += "X " if x[:draw_perc] >= threshold
      txt += "2 " if x[:away_win_perc] >= threshold
      txt += "U " if x[:under_perc] >= threshold
      txt += "O " if x[:over_perc] >= threshold
      txt += "GG" if x[:goal_goal] >= threshold

      pp txt
    end
  end
end
