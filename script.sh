while true; do
    make test-all TESTS="test/ruby/test_shapes.rb"

    if [ $? -ne 0 ]; then
        break
    fi
done
echo "It crashed"
