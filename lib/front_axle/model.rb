module FrontAxle
  module Model

    def self.included(base)
      base.extend(ClassMethods)
    end

    MAX_SIZE = 5000
    DEFAULT_SIZE = 20
    INFINITY = 500_000

    module ClassMethods
      def _search(params, page, order, filter_block, query_block, facet_hash, analyzer = 'synsnowball')
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
            min = params["min#{f}"]
            max = params["max#{f}"]

            next unless min.present? && max.present?

            q[:bool][:must] << { range: { f.to_sym => { gte: min, lte: max } } }
          end
        end

        filters = { :bool => { must: [] } }

        # TODO: no maps in use for now
        if params['bounding_box'].present?
          filters[:bool][:must] << { geo_bounding_box: { location: params['bounding_box'] }}
        elsif params['location_lat'].present? && params['distance'].present?
          filters[:bool][:must] << { geo_distance: { distance: params['distance'],
                                                       distance_type: 'plane',
                                                       location: [params['location_lng'], params['location_lat']] } }
        end

        if klass.const_defined? 'STRING_FACETS'
          klass::STRING_FACETS.each do |t|
            potentially_nested_filters_for(t, filters, params)
          end
        end
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
          finalized_q = query_block.call(q)
        else
          finalized_q = q
        end

        if filter_block.present?
          filters = filter_block.call(filters)
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

        __elasticsearch__.search(query: finalized_q, facets: f, sort: s, filter: filters).per_page(per_page).page(page)
      end

      def potentially_nested_filters_for(t, filters, params)
        return if params[t.to_s].blank?

        if params[t.to_s].class == Array
          filters[:bool][:must] << { terms: { t.to_sym => params[t.to_s] } }
          return
        end

        nested_bool = { :or => { filters: [] } }
        params[t.to_s].each do |k, v|
          nested_bool[:or][:filters] << { terms: { k.to_sym => v } }
        end

        filters[:bool][:must] << nested_bool
      end
    end
  end
end
