require 'httparty'

class Fetcher

  NUMBER_OF_SIMULATIONS = 100000
  FIXTURES_URL = 'http://apiv3.apifootball.com/?action=get_events'.freeze
  HEAD2HEAD_URL = 'http://apiv3.apifootball.com/?action=get_H2H'.freeze
  ODDS_URL = 'https://apiv3.apifootball.com/?action=get_odds'.freeze
  LEAGUES_URL = 'https://apiv3.apifootball.com/?action=get_leagues'.freeze
  POPULAR_LEAGUES = ['175', '244', '302', '168', '152', '207', '266', '3', '4', '354', '372', '24', '178']
  DECAY_RATE = 0.95

  # t: general threshold
  # uot: under over threshold
  # gb: games back
  # leagues: [] -> league ids
  #          'pop' -> popular leagues
  def initialize(params)
    @params = params
  end

  def proposals
    proposals = []

    leagues = if @params[:leagues]
                if @params[:leagues] == 'pop'
                  all_leagues.select { |l| POPULAR_LEAGUES.include?(l['league_id']) }
                else
                  all_leagues.select { |l| @params[:leagues].include?(l['league_id']) }
                end
              else
                all_leagues
              end

    leagues.each do |lg|
      proposals << simulate_league(lg)
    end

    proposals.flatten!

    proposals = above_threshold(proposals) if @params[:t]

    proposals.reject(&:empty?)
  end

  private

  def all_leagues
    @all_leagues ||=
      query = {
        'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad'
      }

    JSON::parse(HTTParty.get(LEAGUES_URL, query: query, verify: false).body.presence || '{}').
      map{ |x| x.slice('league_id', 'country_name', 'league_name')}
  end

  def simulate_league(league)
    games = []

    puts "Scanning #{league['league_name']} - #{league['country_name']}..."
    game_goals = goals_per_game(league['league_id'])

    simulate_games(game_goals)

    #final_games = games.flatten

    #if threshold.present?
    #  final_games = above_threshold(final_games, threshold)
    #end

    #final_games.reject(&:empty?)
  end

 def goals_per_game(league_id)
    estimations = []

    league_fixtures = fixtures(league_id)

    return {} if league_fixtures.is_a?(Hash) && league_fixtures.key?('error')

    puts "#{league_fixtures.count} fixtures found"
    puts "Retrieving Match History for #{@params[:gb]} games back..."

    league_fixtures.each_with_index do |match, i|
      total_goals_away = 0
      total_goals_home = 0
      total_goals_home_conc = 0
      total_goals_away_conc = 0
      sleep(1)
      puts "#{i+1}/#{league_fixtures.count} #{match['match_hometeam_name']} - #{match['match_awayteam_name']}"
      h2h = head_to_head(match['match_hometeam_id'], match['match_awayteam_id'])

      next if h2h.empty?

      #head_to_head_results = h2h['firstTeam_VS_secondTeam'].take(@params[:gb])
      home_team_last_results = h2h['firstTeam_lastResults'].take(@params[:gb])
      away_team_last_results = h2h['secondTeam_lastResults'].take(@params[:gb])

      weights = [1.0]  # Weight for the most recent game

      # Calculate recency-based weights
      (@params[:gb] - 1).times do
        weight = weights.last * DECAY_RATE
        weights.push(weight)
      end

      total_weight = weights.sum
      normalized_weights = weights.map { |weight| weight / total_weight }.reverse
      normalized_weights = [1] * @params[:gb]

      home_team_last_results.each_with_index do |htr, idx|
        if htr['match_hometeam_name'] == match['match_hometeam_name']
          total_goals_home += htr['match_hometeam_score'].to_i * normalized_weights[idx]
          total_goals_home_conc += htr['match_awayteam_score'].to_i * normalized_weights[idx]
        else
          total_goals_home += htr['match_awayteam_score'].to_i * normalized_weights[idx]
          total_goals_home_conc += htr['match_hometeam_score'].to_i * normalized_weights[idx]
        end
      end

      away_team_last_results.each_with_index do |htr, idx|
        if htr['match_awayteam_name'] == match['match_awayteam_name']
          total_goals_away += htr['match_awayteam_score'].to_i * normalized_weights[idx]
          total_goals_away_conc += htr['match_hometeam_score'].to_i * normalized_weights[idx]
        else
          total_goals_away += htr['match_hometeam_score'].to_i * normalized_weights[idx]
          total_goals_away_conc += htr['match_awayteam_score'].to_i * normalized_weights[idx]
        end
      end

      estimations << {
        match_id: match['match_id'],
        home_team: match['match_hometeam_name'],
        away_team: match['match_awayteam_name'],
        home_goals_per_match:  ((total_goals_home / home_team_last_results.count.to_f) + (total_goals_away_conc / away_team_last_results.count.to_f)) / 2.0,
        away_goals_per_match:  ((total_goals_away / away_team_last_results.count.to_f) + (total_goals_home_conc / home_team_last_results.count.to_f)) / 2.0
      }
    end

    estimations
  end

  def fixtures(league_id)
    query = {
      'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad',
      'league_id' => league_id,
      'from' => @params[:from_date],
      'to' => @params[:to_date]
    }

    response= JSON::parse(HTTParty.get(FIXTURES_URL, query: query, verify: false).body.presence || '{}')

    return response if response.is_a?(Hash)

    response.select{|x| (DateTime.parse(@params[:from_date])..DateTime.parse(@params[:to_date]).end_of_day) === DateTime.parse(x['match_date'])}
  end

  def head_to_head(home, away)
    query = {
      'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad',
      'firstTeamId' => home,
      'secondTeamId' => away,
    }

    JSON::parse(HTTParty.get(HEAD2HEAD_URL, query: query, verify: false).body.presence || '{}')
  end

  def simulate_games(games)
    return {} if games.blank?

    puts "Simulating games for #{@params[:gb]} games back. Running #{NUMBER_OF_SIMULATIONS} times..."
    proposals = []

    games.each do |game|
      simulated_scores = []
      NUMBER_OF_SIMULATIONS.times do
        simulated_scores << {
          match_id: game[:match_id],
          home_team: game[:home_team],
          away_team: game[:away_team],
          home: Distribution::Poisson.rng(game[:home_goals_per_match]),
          away: Distribution::Poisson.rng(game[:away_goals_per_match])
        }
      end

      proposals <<
      {
        match_id: game[:match_id],
        home_team: game[:home_team],
        away_team: game[:away_team],
        home_win_perc: simulated_scores.select{|sc| sc[:home] > sc[:away]}.count * 100 / NUMBER_OF_SIMULATIONS.to_f,
        draw_perc: simulated_scores.select{|sc| sc[:home] == sc[:away]}.count * 100 / NUMBER_OF_SIMULATIONS.to_f,
        away_win_perc: simulated_scores.select{|sc| sc[:home] < sc[:away]}.count * 100 / NUMBER_OF_SIMULATIONS.to_f,
        under_perc: simulated_scores.select{|sc| sc[:home] + sc[:away] < 2.5}.count * 100 / NUMBER_OF_SIMULATIONS.to_f,
        over_perc: simulated_scores.select{|sc| sc[:home] + sc[:away] > 2.5}.count * 100 / NUMBER_OF_SIMULATIONS.to_f,
        goal_goal: simulated_scores.select{|sc| sc[:home] > 0 && sc[:away] > 0}.count * 100 / NUMBER_OF_SIMULATIONS.to_f,
        no_goal_goal: simulated_scores.select{|sc| sc[:home] == 0 || sc[:away] == 0}.count * 100 / NUMBER_OF_SIMULATIONS.to_f,
        zero_one_goals: simulated_scores.select{|sc| sc[:home] + sc[:away] < 2}.count * 100 / NUMBER_OF_SIMULATIONS.to_f,
        two_three_goals: simulated_scores.select{|sc| (sc[:home] + sc[:away] == 2) || (sc[:home] + sc[:away] == 3)}.count * 100 / NUMBER_OF_SIMULATIONS.to_f,
        over_three_goals: simulated_scores.select{|sc| sc[:home] + sc[:away] > 3}.count * 100 / NUMBER_OF_SIMULATIONS.to_f
      }
    end

    proposals
  end

  def above_threshold(matches)
    matches.reject(&:empty?).select do |x|
      x.except(:match_id, :home_team, :away_team).values.any?{|v| v >= @params[:t] } ||
        [x[:under_perc] , x[:over_perc]].any? { |p| p > @params[:uot] } ||
        [x[:home_win_perc] + x[:away_win_perc], x[:home_win_perc] + x[:draw_perc], x[:away_win_perc] + x[:draw_perc]].any? { |p| p >  @params[:t] }
    end
  end
end
