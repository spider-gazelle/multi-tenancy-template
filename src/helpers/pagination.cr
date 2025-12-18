module App::Pagination
  # Pagination parameters
  DEFAULT_LIMIT =  20_u32
  MAX_LIMIT     = 100_u32

  # for converting comma separated lists
  # i.e. `"id-1,id-2,id-3"`
  struct ConvertStringArray
    def convert(raw : String)
      raw.split(',').map!(&.strip).reject(&.empty?).uniq!
    end
  end

  # Paginate query results using pg-orm's built-in pagination and set response headers
  def paginate_results(query, item_type : String, route : String? = nil)
    params = search_params
    offset = params["offset"].as(UInt32).to_i
    limit = params["limit"].as(UInt32).to_i

    # Use pg-orm's paginate_by_offset which handles counting properly
    result = query.paginate_by_offset(offset: offset, limit: limit)

    # Set response headers
    # Note: pg-orm's from/to are 1-indexed, but we need 0-indexed for Content-Range
    range_start = result.total == 0 ? 0 : result.from - 1
    range_end = result.total == 0 ? 0 : result.to - 1

    response.headers["X-Total-Count"] = result.total.to_s
    response.headers["Content-Range"] = "#{item_type} #{range_start}-#{range_end}/#{result.total}"

    # Add Link header for next page if available
    if result.has_next?
      route ||= request.path
      next_offset = offset + limit
      query_params = HTTP::Params.build do |form|
        form.add("offset", next_offset.to_s)
        form.add("limit", limit.to_s)
        # Preserve other query parameters
        request.query_params.each do |key, value|
          form.add(key, value) unless key == "offset" || key == "limit"
        end
      end
      response.headers["Link"] = %(<#{route}?#{query_params}>; rel="next")
    end

    # Return the actual records array
    result.records
  end

  # Search helper using ILIKE for field searches or tsvector for general search
  def apply_search(query, search_term : String = "*", fields : Array(String) = [] of String)
    return query if search_term == "*" || search_term.strip.empty?

    # Sanitize search term
    sanitized = search_term.strip
    return query if sanitized.empty?

    # If specific fields are provided, use ILIKE with OR for partial matching
    if fields.any?
      pattern = "%#{sanitized}%"
      # Build OR chain for all fields using String column names
      search_query = query.where_ilike(fields[0], pattern)
      fields[1..].each do |field|
        search_query = search_query.or(query.where_ilike(field, pattern))
      end
      search_query
    else
      # Use the pre-computed search_vector column with prefix search for partial word matching
      # This allows "tech" to match "Technology"
      query.search_vector("#{sanitized}:*", :search_vector, config: "simple")
    end
  end

  # Sort helper
  def apply_sort(query, sort_field : String, sort_order : String = "asc")
    return query if sort_field.empty?

    order = sort_order.downcase == "desc" ? "DESC" : "ASC"
    # Sanitize field name to prevent SQL injection
    safe_field = sort_field.gsub(/[^a-z_]/, "")
    return query if safe_field.empty?

    query.order("#{safe_field} #{order}")
  end
end
