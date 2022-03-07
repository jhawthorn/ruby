require '-test-/marshal/internal_ivar'

v = Bug::Marshal::InternalIVar.new("hello", "world", "bye")
p v.normal == "hello"
