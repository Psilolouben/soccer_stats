require 'httparty'

class Fetcher
  FIXTURES_URL = 'http://apiv2.apifootball.com/?action=get_events'.freeze
  HEAD2HEAD_URL = 'http://apiv2.apifootball.com/?action=get_H2H'.freeze
  ODDS_URL = 'https://apiv2.apifootball.com/?action=get_odds'.freeze


  LEAGUES = {
    primera: '468',
    superleague: '209',
    premier: '148',
    championship: '149',
    bundesliga: '195',
    ligue_1: '176',
    eredivisie: '343',
    serie_a: '262'
  }.freeze

  attr_reader :params, :league_id

  # from_date, to_date, league_id, api_key
  # f = Fetcher.new(params: {from_date: Date.today.to_s, to_date: Date.tomorrow.to_s, league_id: '149'})
  def initialize(params: {})
    @params = params
    @league_id = params[:league_id]
  end

  def fixtures
    query = {
      'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad',
      'league_id' => @league_id,
      'from' => params[:from_date],
      'to' => params[:to_date]
    }
    JSON::parse(HTTParty.get(FIXTURES_URL, query: query).body)
  end

  def head_to_head(home, away)
    query = {
      'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad',
      'firstTeam' => home,
      'secondTeam' => away,
    }
    JSON::parse(HTTParty.get(HEAD2HEAD_URL, query: query).body)
  end

  def self.get_leagues
    LEAGUES.keys
  end

  def calculate(games_back = 5)
    estimations = []

    fixtures.each do |match|
      next if match.class != Hash

      home_wins = 0
      away_wins = 0
      draws = 0
      unders = 0
      overs = 0
      home_scored = 0
      away_scored = 0

      h2h = head_to_head(match['match_hometeam_name'], match['match_awayteam_name'])

      head_to_head_results = h2h['firstTeam_VS_secondTeam'].take(games_back)
      home_team_last_results = h2h['firstTeam_lastResults'].take(games_back)
      away_team_last_results = h2h['secondTeam_lastResults'].take(games_back)

      samples_count = head_to_head_results.count + home_team_last_results.count + away_team_last_results.count

      head_to_head_results.each do |htr|
        # Win/Draw
        if htr['match_hometeam_score'].to_i == htr['match_awayteam_score'].to_i
          draws += 0.5
        elsif htr['match_hometeam_score'].to_i > htr['match_awayteam_score'].to_i
          if htr['match_hometeam_name'] == match['match_hometeam_name']
            home_wins += 0.5
          else
            away_wins += 0.5
          end
        else
          if htr['match_awayteam_name'] == match['match_hometeam_name']
            home_wins += 0.5
          else
            away_wins += 0.5
          end
        end

        # U/O
        if htr['match_hometeam_score'].to_i + htr['match_awayteam_score'].to_i > 2.5
          overs += 0.5
        else
          unders += 0.5
        end

        # G-G
        if htr['match_hometeam_name'] == match['match_hometeam_name']
          if htr['match_hometeam_score'].to_i > 0
            home_scored += 0.5
          end
          if htr['match_awayteam_score'].to_i > 0
            away_scored += 0.5
          end
        else
          if htr['match_hometeam_score'].to_i > 0
            away_scored += 0.5
          end
          if htr['match_awayteam_score'].to_i > 0
            home_scored += 0.5
          end
        end
      end

      home_team_last_results.each do |htr|
        if htr['match_hometeam_score'].to_i == htr['match_awayteam_score'].to_i
          draws += 1
        elsif htr['match_hometeam_score'].to_i > htr['match_awayteam_score'].to_i
          if htr['match_hometeam_name'] == match['match_hometeam_name']
            home_wins += 1
          else
            away_wins += 1
          end
        else
          if htr['match_awayteam_name'] == match['match_hometeam_name']
            home_wins += 1
          else
            away_wins += 1
          end
        end

        if htr['match_hometeam_score'].to_i + htr['match_awayteam_score'].to_i > 2.5
          overs += 1
        else
          unders += 1
        end

        # G-G
        if htr['match_hometeam_name'] == match['match_hometeam_name']
          if htr['match_hometeam_score'].to_i > 0
            home_scored += 1
          end
        else
          if htr['match_awayteam_score'].to_i > 0
            home_scored += 1
          end
        end
      end

      away_team_last_results.each do |htr|
        if htr['match_hometeam_score'].to_i == htr['match_awayteam_score'].to_i
          draws += 1
        elsif htr['match_hometeam_score'].to_i > htr['match_awayteam_score'].to_i
          if htr['match_hometeam_name'] == match['match_awayteam_name']
            away_wins += 1
          else
            home_wins += 1
          end
        else
          if htr['match_awayteam_name'] == match['match_awayteam_name']
            away_wins += 1
          else
            home_wins += 1
          end
        end

        if htr['match_hometeam_score'].to_i + htr['match_awayteam_score'].to_i > 2.5
          overs += 1
        else
          unders += 1
        end

        # G-G
        if htr['match_awayteam_name'] == match['match_awayteam_name']
          if htr['match_awayteam_score'].to_i > 0
            away_scored += 1
          end
        else
          if htr['match_hometeam_score'].to_i > 0
            away_scored += 1
          end
        end
      end

      estimations << {
        match_id: match['match_id'],
        home_team: match['match_hometeam_name'],
        away_team: match['match_awayteam_name'],
        home_win_perc: home_wins * (100.0/samples_count),
        away_win_perc: away_wins * (100.0/samples_count),
        draw_perc: draws * (100.0/samples_count),
        under_perc: unders * (100.0/samples_count),
        over_perc: overs * (100.0/samples_count),
        goal_goal: (home_scored + away_scored) * 100.0 / samples_count
      }
    end

    estimations
  end

  def get_odds(match_id)
    query = {
      'APIkey' => '95ccd167a397363723112202c736a04db13b22494dee1e60acc2a2f94e949fad',
      'from' => params[:from_date],
      'to' => params[:to_date],
      'match_id' => match_id,
    }
    JSON::parse(HTTParty.get(ODDS_URL, query: query).body)
  end

  def proposals(threshold = 70)
    games = []
      LEAGUES.each do |key, value|
        puts "Scanning #{key}..."
        @league_id = value.to_s
        games << calculate
      end

    games.flatten.select{|x| x.except(:match_id, :home_team, :away_team).values.any?{|v| v >= threshold }}
  end
end
