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
        # Elasticsearch.configure { logger 'elasticsearch-rails.log' }

        q = {}
        q = {
          # must: {
            match: {
              title: {
                query: '*',
                # analyzer: analyzer,
                operator: 'AND',
                zero_terms_query: "all"
                }
              }
            # }
          }
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

        __elasticsearch__.search(query: q, facets: f).per_page(15).page(page)


        # __elasticsearch__.search do |s|
        #   qqq = lambda do |q|
        #     q.boolean do
        #       if params['query'].present?
        #         if analyzer.present?
        #           must { match :_all, params['query'], { operator: 'AND', analyzer: analyzer } }
        #         else
        #           must { match :_all, params['query'], operator: 'AND' }
        #         end
        #       else
        #         must { string '*' }
        #       end
        #       must { range :updated_at, from: params['updated_since'] } if params['updated_since'].present?
        #       if klass.const_defined? 'SLIDEY_FACETS'
        #         klass::SLIDEY_FACETS.select { |f| !f[:i_will_search] }.each do |f|
        #           min = params["min#{f[:name]}"]
        #           max = params["max#{f[:name]}"]
        #           if min.present? && max.present?
        #             if f[:type] == 'money'
        #               max = max.to_f * 1_000_000
        #               min = min.to_f * 1_000_000
        #             end

        #             must { range f[:name], from: min, to: max }
        #           end
        #         end
        #       end
        #       if klass.const_defined? 'DATE_FACETS'
        #         klass::DATE_FACETS.each do |f|
        #           min = params["min#{f}"]
        #           max = params["max#{f}"]

        #           must { range f.to_s, from: min, to: max } if min.present? && max.present?
        #         end
        #       end
        #
        #   end

        #   if params['bounding_box'].present?
        #     s.query do |q|
        #       q.filtered do
        #         filter :geo_bounding_box, location: params['bounding_box']
        #         query(&qqq)
        #       end
        #     end
        #   elsif params['location_lat'].present? && params['distance'].present?
        #     s.query do |q|
        #       q.filtered do

        #         filter :geo_distance, distance: params['distance'], distance_type: 'plane',
        #                               location: [params['location_lng'], params['location_lat']]
        #         query(&qqq)
        #       end
        #     end
        #   else
        #     s.query(&qqq)
        #   end

        #   facet_block.call(s) if facet_block


        #   search_size = params[:per] || DEFAULT_SIZE

        #   if order.present?
        #     desc = order.match(/_desc$/)
        #     key = order.gsub(/_desc$/, '')
        #     s.sort do
        #       by((klass.mapping.key?(("sort_#{key}").to_sym) ? "sort_#{key}" : key), desc ? 'desc' : 'asc')
        #       by '_score' if key != '_score'
        #     end
        #   end
        #   if page > 0
        #     s.from((page - 1) * search_size)
        #     s.size search_size
        #   else
        #     s.size MAX_SIZE
        #   end
        # end


      end
    end
  end
end
