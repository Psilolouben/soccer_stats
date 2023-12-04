require 'httparty'

class Fetcher

  NUMBER_OF_SIMULATIONS = 100000
  FIXTURES_URL = 'http://apiv3.apifootball.com/?action=get_events'.freeze
  HEAD2HEAD_URL = 'http://apiv3.apifootball.com/?action=get_H2H'.freeze
  ODDS_URL = 'https://apiv3.apifootball.com/?action=get_odds'.freeze
  LEAGUES_URL = 'https://apiv3.apifootball.com/?action=get_leagues'.freeze
  PREDICTIONS_URL = 'https://apiv3.apifootball.com/?action=get_predictions'.freeze
  STATISTICS_URL = 'https://apiv3.apifootball.com/?action=get_statistics'.freeze

  POPULAR_LEAGUES = ['175', '244', '302', '168', '152', '207', '266', '3', '4',
                    '683', '344', '354', '372', '24', '178', '56', '322', '135',
                    '308', '259', '124', '279', '307', '253', '134', '63']

  ELITE_LEAGUES = [ '3', '4', '175', '244', '302', '168', '152', '207']

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
                elsif @params[:leagues] == 'elite'
                  all_leagues.select { |l| ELITE_LEAGUES.include?(l['league_id']) }
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

    export_to_csv(proposals.reject(&:empty?))

    if @params[:pp]
      pp_bets(proposals.reject(&:empty?));0
    else
      return proposals.reject(&:empty?)
    end
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

    if league_fixtures.count > 0
      puts "#{league_fixtures.count} fixtures found"
      puts "Retrieving Match History for #{@params[:gb]} games back..."
    end

    league_fixtures.each_with_index do |match, i|
      total_goals_away = 0
      total_goals_home = 0
      total_goals_home_conc = 0
      total_goals_away_conc = 0
      total_goals_home_half = 0
      total_goals_home_conc_half = 0
      total_goals_away_half = 0
      total_goals_away_conc_half = 0
      total_corners = 0
      total_yellow = 0
      total_red = 0

      sleep(1)
      puts "#{i+1}/#{league_fixtures.count} #{match['match_hometeam_name']} - #{match['match_awayteam_name']}"
      h2h = head_to_head(match['match_hometeam_id'], match['match_awayteam_id'])

      next if h2h.empty?
      #head_to_head_results = h2h['firstTeam_VS_secondTeam'].take(@params[:gb])
      home_team_last_results = h2h['firstTeam_lastResults'].select{|x| x['league_id'] == league_id.to_s}.take(@params[:gb])
      away_team_last_results = h2h['secondTeam_lastResults'].select{|x| x['league_id'] == league_id.to_s}.take(@params[:gb])

      weights = [1.0]  # Weight for the most recent game

      # Calculate recency-based weights
      (@params[:gb] - 1).times do
        weight = weights.last * DECAY_RATE
        weights.push(weight)
      end

      total_weight = weights.sum
      #normalized_weights = weights#.map { |weight| weight / total_weight }
      normalized_weights = [1] * @params[:gb]

      home_team_last_results.each_with_index do |htr, idx|
        stats = statistics(htr['match_id'])
        total_corners += stats[htr['match_id']]['statistics'].select{|x| x['type'] == 'Corners'}.sum{|x| x['home'].to_i + x['away'].to_i }
        total_yellow += stats[htr['match_id']]['statistics'].select{|x| x['type'] == 'Yellow Cards'}.sum{|x| x['home'].to_i + x['away'].to_i }
        total_red += stats[htr['match_id']]['statistics'].select{|x| x['type'] == 'Red Cards'}.sum{|x| x['home'].to_i + x['away'].to_i }

        if htr['match_hometeam_id'] == match['match_hometeam_id']
          total_goals_home += htr['match_hometeam_score'].to_i * normalized_weights[idx]
          total_goals_home_conc += htr['match_awayteam_score'].to_i * normalized_weights[idx]
          total_goals_home_half += htr['match_hometeam_halftime_score'].to_i * normalized_weights[idx]
          total_goals_home_conc_half += htr['match_awayteam_halftime_score'].to_i * normalized_weights[idx]
        else
          total_goals_home += htr['match_awayteam_score'].to_i * normalized_weights[idx]
          total_goals_home_conc += htr['match_hometeam_score'].to_i * normalized_weights[idx]
          total_goals_home_half += htr['match_awayteam_halftime_score'].to_i * normalized_weights[idx]
          total_goals_home_conc_half += htr['match_hometeam_halftime_score'].to_i * normalized_weights[idx]
        end
      end

      away_team_last_results.each_with_index do |htr, idx|
        if htr['match_awayteam_id'] == match['match_awayteam_id']
          total_goals_away += htr['match_awayteam_score'].to_i * normalized_weights[idx]
          total_goals_away_conc += htr['match_hometeam_score'].to_i * normalized_weights[idx]
          total_goals_away_half += htr['match_awayteam_halftime_score'].to_i * normalized_weights[idx]
          total_goals_away_conc_half += htr['match_hometeam_halftime_score'].to_i * normalized_weights[idx]
        else
          total_goals_away += htr['match_hometeam_score'].to_i * normalized_weights[idx]
          total_goals_away_conc += htr['match_awayteam_score'].to_i * normalized_weights[idx]
          total_goals_away_half += htr['match_hometeam_halftime_score'].to_i * normalized_weights[idx]
          total_goals_away_conc_half += htr['match_awayteam_halftime_score'].to_i * normalized_weights[idx]
        end
      end

      estimations << {
        match_id: match['match_id'],
        home_team: match['match_hometeam_name'],
        away_team: match['match_awayteam_name'],
        home_goals_per_match:  ((total_goals_home / home_team_last_results.count.to_f) + (total_goals_away_conc / away_team_last_results.count.to_f)) / 2.0,
        away_goals_per_match:  ((total_goals_away / away_team_last_results.count.to_f) + (total_goals_home_conc / home_team_last_results.count.to_f)) / 2.0,
        home_goals_half:  ((total_goals_home_half / home_team_last_results.count.to_f) + (total_goals_away_conc_half / away_team_last_results.count.to_f)) / 2.0,
        away_goals_half:  ((total_goals_away_half / away_team_last_results.count.to_f) + (total_goals_home_conc_half / home_team_last_results.count.to_f)) / 2.0,
        total_corners_per_match: (total_corners / home_team_last_results.count.to_f),
        total_yellow_per_match: (total_yellow / home_team_last_results.count.to_f),
        total_red_per_match: (total_red / home_team_last_results.count.to_f)
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

    fixt = response.select{|x| (DateTime.parse(@params[:from_date])..DateTime.parse(@params[:to_date]).end_of_day) === DateTime.parse(x['match_date'])}

    if DateTime.parse(@params[:from_date]) == Date.today
      fixt = fixt.select{|x| x['match_time'].split(':').first.to_i + 1 > Time.now.hour }
    end

    fixt
  end

  def statistics(match_id)
    query = {
      'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad',
      'match_id' => match_id
    }

    JSON::parse(HTTParty.get(STATISTICS_URL, query: query, verify: false).body.presence || '{}')
  end

  def head_to_head(home, away)
    query = {
      'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad',
      'firstTeamId' => home,
      'secondTeamId' => away,
    }

    JSON::parse(HTTParty.get(HEAD2HEAD_URL, query: query, verify: false).body.presence || '{}')
  end

  def predictions(match_id)
    query = {
      'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad',
      'match_id' => match_id
    }

    JSON::parse(HTTParty.get(PREDICTIONS_URL, query: query, verify: false).body.presence || '{}')
  end

  def simulate_games(games)
    return {} if games.blank?

    puts "Simulating games for #{@params[:gb]} games back. Running #{NUMBER_OF_SIMULATIONS} times..."
    proposals = []

    games.each do |game|
      #apf_predictions = predictions(game[:match_id])

      simulated_scores = []

      NUMBER_OF_SIMULATIONS.times do
        simulated_scores << {
          match_id: game[:match_id],
          home_team: game[:home_team],
          away_team: game[:away_team],
          home: Distribution::Poisson.rng(game[:home_goals_per_match]),
          away: Distribution::Poisson.rng(game[:away_goals_per_match]),
          home_half: Distribution::Poisson.rng(game[:home_goals_half]),
          away_half: Distribution::Poisson.rng(game[:away_goals_half]),
          corners: Distribution::Poisson.rng(game[:total_corners_per_match]),
          yellow_cards: Distribution::Poisson.rng(game[:total_yellow_per_match]),
          red_cards: Distribution::Poisson.rng(game[:total_red_per_match])
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
        over_three_goals: simulated_scores.select{|sc| sc[:home] + sc[:away] > 3}.count * 100 / NUMBER_OF_SIMULATIONS.to_f,
        over_goals_half: {
          '05' => simulated_scores.select{|sc| sc[:home_half] + sc[:away_half] > 0}.count * 100 / NUMBER_OF_SIMULATIONS.to_f,
          '15' => simulated_scores.select{|sc| sc[:home_half] + sc[:away_half] > 1.5}.count * 100 / NUMBER_OF_SIMULATIONS.to_f,
          '25' => simulated_scores.select{|sc| sc[:home_half] + sc[:away_half] > 2.5}.count * 100 / NUMBER_OF_SIMULATIONS.to_f
        },
        over_corners: {
          '8' => simulated_scores.count{|x| x[:corners] > 8 } * 100 / NUMBER_OF_SIMULATIONS.to_f,
          '9' => simulated_scores.count{|x| x[:corners] > 9 } * 100 / NUMBER_OF_SIMULATIONS.to_f,
          '10' => simulated_scores.count{|x| x[:corners] > 10 } * 100 / NUMBER_OF_SIMULATIONS.to_f,
          '11' => simulated_scores.count{|x| x[:corners] > 11 } * 100 / NUMBER_OF_SIMULATIONS.to_f
        },
        over_cards: {
          '3.5' => simulated_scores.count{|x| (x[:yellow_cards] + x[:red_cards]) > 3.5 } * 100 / NUMBER_OF_SIMULATIONS.to_f,
          '4.5' => simulated_scores.count{|x| (x[:yellow_cards] + x[:red_cards]) > 4.5 } * 100 / NUMBER_OF_SIMULATIONS.to_f,
          '5.5' => simulated_scores.count{|x| (x[:yellow_cards] + x[:red_cards]) > 5.5 } * 100 / NUMBER_OF_SIMULATIONS.to_f
        },
        over_05_red_cards: simulated_scores.count{|x| x[:red_cards] > 0} * 100 / NUMBER_OF_SIMULATIONS.to_f
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

  def pp_bets(matches)
    return matches unless (@params[:pp] && (@params[:t] || @params[:uot]))

    matches.each do |m|
      bet = []
      if m[:home_win_perc] + m[:away_win_perc] > @params[:t]
        bet << {res: "12", prob: m[:home_win_perc] + m[:away_win_perc]}
      elsif m[:home_win_perc] + m[:draw_perc] > @params[:t]
        bet << {res: "1X", prob: m[:home_win_perc] + m[:draw_perc]}
      elsif m[:away_win_perc] + m[:draw_perc] > @params[:t]
        bet << {res: "X2", prob: m[:away_win_perc] + m[:draw_perc]}
      end
      bet << {res: "1", prob: m[:home_win_perc] }
      bet << {res: "2", prob: m[:away_win_perc]}
      bet << {res: "X", prob: m[:draw_perc]}

      bet << { res: "U", prob: m[:under_perc] } if m[:under_perc] > @params[:uot]
      bet << { res: "O", prob: m[:over_perc] } if m[:over_perc] > @params[:uot]
      bet << { res: "1", prob: m[:home_win_perc] } if m[:home_win_perc] > @params[:t]
      bet << { res: "X", prob: m[:draw_perc] } if m[:draw_perc] > @params[:t]
      bet << { res: "2", prob: m[:away_win_perc] } if m[:away_win_perc] > @params[:t]

      pp "#{m[:home_team]} - #{m[:away_team]}"
      bet.each do |x|
        pp "#{x[:res]} - #{x[:prob]}"
      end
    end
  end

  def export_to_csv(proposals)
    CSV.open("bet_proposals.csv", "w", col_sep: ';') do |csv|
      csv << ['Home', 'Away', '1', 'X', '2', 'U', 'O', 'APIF1', 'APIFX', 'APIF2', 'APIFU', 'APIFO']
      proposals.each do |game|
        csv << [
          game[:home_team].to_s,
          game[:away_team].to_s,
          game[:home_win_perc].to_s.gsub('.',','),
          game[:draw_perc].to_s.gsub('.',','),
          game[:away_win_perc].to_s.gsub('.',','),
          game[:under_perc].to_s.gsub('.',','),
          game[:over_perc].to_s.gsub('.',','),
          game[:apf_home_win_perc].to_s.gsub('.',','),
          game[:apf_draw_perc].to_s.gsub('.',','),
          game[:apf_away_win_perc].to_s.gsub('.',','),
          game[:apf_under_perc].to_s.gsub('.',','),
          game[:apf_over_perc].to_s.gsub('.',',')
        ]
      end
    end;0
  end
end
