tt = ObjectSpace.shape_transition_tree

def iterate_over_shape(shape)
  add_ids(shape)
  shape[:edges].each do |edge|
    next_shape = edge[1]
    add_edges(shape, next_shape, edge[0])
    iterate_over_shape(next_shape)
  end
end

def add_ids(shape)
  @id_to_labels += "    #{shape[:id]} [label=\"ID: #{shape[:id]}, Transitions: #{shape[:transition_count]}, Parent: #{shape[:parent_id}]\"]\n"
  # @id_to_labels += "    #{shape[:id]} [label=\"#{shape[:id]}, Number of transitions: #{shape[:transition_count]}, seen: #{shape[:seen_ivars]}\"]\n"
end

def add_edges(shape, next_shape, edge_var)
  @edges += "    #{shape[:id]} -> #{next_shape[:id]} [label=\"#{edge_var}\"]\n"
end

def print_digraph(transition_tree)
  @id_to_labels = ""
  @edges = ""

  iterate_over_shape(transition_tree)
  puts "digraph {"
  puts @id_to_labels
  puts "\n"
  puts @edges
  puts "}"
end

print_digraph(tt)
