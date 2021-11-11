require 'httparty'

class Fetcher
  FIXTURES_URL = 'http://apiv2.apifootball.com/?action=get_events'.freeze
  HEAD2HEAD_URL = 'http://apiv2.apifootball.com/?action=get_H2H'.freeze
  ODDS_URL = 'https://apiv2.apifootball.com/?action=get_odds'.freeze
  LEAGUES_URL = 'https://apiv3.apifootball.com/?action=get_leagues'.freeze

  LEAGUES = {
    primera: '468', la_liga2: '469', superleague: '209', premier: '148', championship: '149',
    league_one: '150', league_two: '151', bundesliga: '195', ligue_1: '176', ligue_2: '177',
    eredivisie: '343', serie_a: '262', serie_b: '263', chl: '589', europa: '590',
    brazil_1: '68', primeira_liga: '391', jupiter_league: '51', premier_scotland: '423',
    super_league_swiss: '491', super_lig_turkey: '511', tipico_bundesliga_au: '33',
    vysshaya_liga_bel: '47', premier_league_bos: '63', parva_liga_bu: '78',
    hnl_cro: '110', first_division_cy: '114', liga_cz: '120',
    superliga_dk: '130', meistriliga_est: '158', veikkausliga_fin: '166',
    otp_banka_liga_hu: '224', premier_ireland: '253', liga_latvia: '9673',
    national_lux: '310', prva_crnogorska_monte: '334', nifl_premier: '354',
    ekstraklasa_pol: '381', liga_1_romania: '400', fortuna_slovakia: '443',
    premier_ukraine: '523', pepsideild: '232', leumit_isr: '258',
    a_lyga_lithuania: '306', divizia_nationala_mol: '331', eliteserien_nor: '359',
    premier_russia: '407', super_liga_servia: '434', prva_liga_slovenia: '453',
    allsvenskan_swe: '481', cymru_wales: '551'
  }.freeze

  attr_reader :params, :league_id

  # from_date, to_date, league_id, api_key
  # f = Fetcher.new(params: {from_date: Date.today.to_s, to_date: Date.tomorrow.to_s, league_id: '149'})
  def initialize(params: {})
    @params = params
    @league_id = params[:league_id]
  end

  def leagues
    @leagues ||=
      query = {
        'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad'
      }

    response= JSON::parse(HTTParty.get(LEAGUES_URL, query: query, verify: false).body.presence || '{}')
  end

  def success_rate
    SoccerStat.last.correct_guesses / SoccerStat.last.total_guesses.to_f
  end

  def update_success_rate(correct_guesses, total_guesses)
    sstat = SoccerStat.last
    sstat.update!(correct_guesses: sstat.correct_guesses + correct_guesses, total_guesses: sstat.total_guesses + total_guesses)
  end

  def proposals(threshold = nil, games_back = 5)
    games = []

    leagues.each do |lg|
      puts "Scanning #{lg['league_name']} - #{lg['country_name']}..."
      @league_id = lg['league_id']
      games << simulate(goals_per_game(games_back), games_back)
    end
    final_games = games.flatten

    if threshold.present?
      final_games = above_threshold(final_games, threshold)
    end

    final_games.reject(&:empty?)
  end

  def fixtures
    query = {
      'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad',
      'league_id' => @league_id,
      'from' => params[:from_date],
      'to' => params[:to_date]
    }

    response= JSON::parse(HTTParty.get(FIXTURES_URL, query: query, verify: false).body.presence || '{}')

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
    JSON::parse(HTTParty.get(HEAD2HEAD_URL, query: query, verify: false).body.presence || '{}')
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
      total_goals_home_conc = 0
      total_goals_away_conc = 0
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
          total_goals_home_conc += htr['match_awayteam_score'].to_i
        else
          total_goals_home += htr['match_awayteam_score'].to_i
          total_goals_home_conc += htr['match_hometeam_score'].to_i
        end
      end

      away_team_last_results.each do |htr|
        if htr['match_awayteam_name'] == match['match_awayteam_name']
          total_goals_away += htr['match_awayteam_score'].to_i
          total_goals_away_conc += htr['match_hometeam_score'].to_i
        else
          total_goals_away += htr['match_hometeam_score'].to_i
          total_goals_away_conc += htr['match_awayteam_score'].to_i
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
        goal_goal: simulated_scores.select{|sc| sc[:home] > 0 && sc[:away] > 0}.count * 100 / number_of_simulations.to_f,
        no_goal_goal: simulated_scores.select{|sc| sc[:home] == 0 || sc[:away] == 0}.count * 100 / number_of_simulations.to_f,
        zero_one_goals: simulated_scores.select{|sc| sc[:home] + sc[:away] < 2}.count * 100 / number_of_simulations.to_f,
        two_three_goals: simulated_scores.select{|sc| (sc[:home] + sc[:away] == 2) || (sc[:home] + sc[:away] == 3)}.count * 100 / number_of_simulations.to_f,
        over_three_goals: simulated_scores.select{|sc| sc[:home] + sc[:away] > 3}.count * 100 / number_of_simulations.to_f
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
      txt += "1 (#{x[:home_win_perc]}%)" if x[:home_win_perc] >= threshold
      txt += "X (#{x[:draw_perc]}%)" if x[:draw_perc] >= threshold
      txt += "2 (#{x[:away_win_perc]}%)" if x[:away_win_perc] >= threshold
      txt += "U (#{x[:under_perc]}%)" if x[:under_perc] >= threshold
      txt += "O (#{x[:over_perc]}%)" if x[:over_perc] >= threshold
      txt += "GG (#{x[:goal_goal]}%)" if x[:goal_goal] >= threshold
      txt += "NGG (#{x[:no_goal_goal]}%)" if x[:no_goal_goal] >= threshold

      pp txt
    end
  end
end
