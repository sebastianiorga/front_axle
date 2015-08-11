module FrontAxle
  module Model

    def self.included(base)
      base.extend(ClassMethods)
    end

    MAX_SIZE = 5000
    DEFAULT_SIZE = 20
    INFINITY = 500_000

    module ClassMethods
      def _search(params, page, order, query_block, facet_hash, analyzer = 'synsnowball')
        klass = self
        page = 1 if page == 0 || !page
        per_page = params[:per_page]
        per_page = 15 if params[:per_page].blank?
        # TODO: configure logger
        # Elasticsearch.configure { logger 'elasticsearch-rails.log' }

        # QUERY
        q = {}

        if params['query'].present?
          if analyzer.present?
            query = {
              must: [{
                match: {
                  _all: {
                    query: params['query'],
                    operator: 'AND',
                    analyzer: analyzer
                    }
                  }
                }]
              }
          else
            query = {
              must: [{
                match: {
                  _all: {
                    query: params['query'],
                    operator: 'AND'
                    }
                  }
                }]
              }
          end
        else
          query = {
              must: [{
                match_all: {}
              }]
            }
        end
        q[:bool] = query

        # TODO: what is this?
        # must { range :updated_at, from: params['updated_since'] } if params['updated_since'].present?

        if klass.const_defined? 'SLIDEY_FACETS'
          klass::SLIDEY_FACETS.select { |f| !f[:i_will_search] }.each do |f|
            min = params["min#{f[:name]}"]
            max = params["max#{f[:name]}"]
            if min.present? && max.present?
              if f[:type] == 'money'
                max = max.to_f * 1_000_000
                min = min.to_f * 1_000_000
              end

              q[:bool][:must] << { range: { f[:name] => { gte: min, lte: max } } }
            end
          end
        end
        if klass.const_defined? 'DATE_FACETS'
          klass::DATE_FACETS.each do |f|
            next unless min.present? && max.present?

            min = params["min#{f}"]
            max = params["max#{f}"]

            q[:bool][:must] << { range: { f.to_sym => { gte: min, lte: max } } }
          end
        end
        if klass.const_defined? 'STRING_FACETS'
          klass::STRING_FACETS.each do |t|
            next if params[t.to_s].blank?

            q[:bool][:must] << { terms: { t.to_sym => params[t.to_s] } }
          end
        end

        # TODO: no maps in use for now
        # if params['bounding_box'].present?
        #    s.query do |q|
        #      q.filtered do
        #        filter :geo_bounding_box, location: params['bounding_box']
        #        query(&qqq)
        #      end
        #    end
        #  elsif params['location_lat'].present? && params['distance'].present?
        #    s.query do |q|
        #      q.filtered do

        #        filter :geo_distance, distance: params['distance'], distance_type: 'plane',
        #                              location: [params['location_lng'], params['location_lat']]
        #        query(&qqq)
        #      end
        #    end
        #  else
        #    s.query(&qqq)
        #  end

        # FACETS
        f = facet_hash
        if klass.const_defined? 'STRING_FACETS'
          klass::STRING_FACETS.each do |facet|
            t = Array(facet)[0]
            # size = Array(facet)[1] || 1000
            f[t.to_sym] = { terms: { field: t.to_sym } }
          end
        end

        if klass.const_defined? 'SLIDEY_FACETS'
          klass::SLIDEY_FACETS.select { |f| !f[:i_will_facet] }.each do |facet|
            f[facet[:name].to_sym] = { histogram: { field: facet[:name].to_sym, interval: facet[:interval] } }
          end
        end

        if klass.const_defined? 'DATE_FACETS'
          klass::DATE_FACETS.each do |facet|
            f[facet[:name].to_sym] = { date_histogram: { field: facet[:name].to_sym, interval: facet.fetch(:interval) { 'month' } } }
          end
        end

        if query_block.present?
          customized_q = query_block.call(q)
        else
          customized_q = q
        end

        s = []
        if order.present?
          desc = order.match(/_desc$/)
          direction = desc ? 'desc' : 'asc'
          k = order.gsub(/_desc$/, '')
          props = klass.mapping.to_hash.values.first[:properties]

          key = props.key?(("sort_#{k}").to_sym) ? "sort_#{k}" : k

          s << { key => direction }
          s << '_score' if key != '_score'
        end

        __elasticsearch__.search(query: q, facets: f, sort: s).per_page(per_page).page(page)
      end
    end
  end
end
