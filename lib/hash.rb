class Hash
  # Results in
  # Genertaing a flattened array of values of the common keys.
  # {:a => 1, :b => [[2, 3], 4]}.join_merge({:c => [1, 2], :b => [2, 3]}) => {:a=>1, :b=>[2, 3, 4, 2, 3], :c=>[1, 2]}

  def join_merge(hash)
    new_hash = self.merge(hash)
    unless (self.keys & hash.keys).empty?
      add_to_self = {}
      (self.keys & hash.keys).each do |key|
        value = []
        value << self[key]
        value << hash[key]
        add_to_self.merge!(key => value.flatten)
      end
      new_hash.merge!(add_to_self)
    end
    new_hash
  end 
end
