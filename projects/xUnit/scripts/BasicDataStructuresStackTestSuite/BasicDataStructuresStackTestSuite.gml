

function BasicDataStructuresStackTestSuite() : TestSuite() constructor {

	addFact("ds_stack_create_test", function() {
			
		var stack = ds_stack_create();
		
		var output = ds_exists(stack, ds_type_stack);
		assert_true(output, "#1 ds_stack_create(), failed to create stack");
			
		// Clean up
		ds_stack_destroy(stack);
	})

	addFact("ds_stack_push_pop_top_test", function() {
			
		var stack, output;
			
		stack = ds_stack_create();
			
		ds_stack_push(stack, 50, 100, 200);
		assert_stack_size(stack, 3, "#1 ds_stack_push(...), failed to push the correct number of arguments");
			
		output = ds_stack_top(stack);
		assert_equals(output, 200, "#2 ds_stack_top(...), failed to identify the top element of the stack");
			
		output = ds_stack_pop(stack);
		assert_equals(output, 200, "#3.1 ds_stack_pop(...), failed to retrieve the top element of the stack");
		assert_stack_size(stack, 2, "#3.2 ds_stack_push(...), failed to push the correct number of arguments");
			
		output = ds_stack_pop(stack); // size 1
		output = ds_stack_pop(stack); // size 0
			
		output = ds_stack_pop(stack);
		assert_equals(output, undefined, "#4 ds_stack_pop(...), popping from empty stack should return 'undefined'");
			
		ds_stack_destroy(stack);			
	})
		
	addFact("ds_stack_copy_test", function() {

		var stack, copiedStack;

		stack = ds_stack_create();
		ds_stack_push(stack, 50, 100, 200);
		
		copiedStack = ds_stack_create()
		ds_stack_copy(copiedStack, stack);
		
		assert_stack_equals(stack, copiedStack, "#1 ds_stack_copy(..), failed to correctly copy the stack");

		ds_stack_destroy(stack);
		ds_stack_destroy(copiedStack);
			
	})

	addFact("ds_stack_read_write", function() {
		
		var stack, output;

		// Generated by C++ runner using a stack of ( 50, 100, 200, "hello", [ 3.14159, "world" ] )
		var v103_encoded = "6700000005000000000000000000000000004940000000000000000000005940000000000000000000006940010000000500000068656C6C6F0200000002000000000000006E861BF0F92109400100000005000000776F726C64";

		// Generated by HTML5 runner using a stack of ( 50, 100, 200, "hello", 3.14159, "world" )
		var v102_encoded = "6600000006000000000000000000000000004940000000000000000000005940000000000000000000006940010000000500000068656C6C6F000000006E861BF0F92109400100000005000000776F726C64"
			

		stack = ds_stack_create();
		ds_stack_push(stack, 50, 100, 200, "hello", [ 3.14159, "world" ]);
			
		output = ds_stack_write(stack);
		assert_equals(output, v103_encoded, "#1 ds_stack_write(), doesn't match pre-baked encoded string");
			
		output = ds_stack_empty(stack);
		assert_false(output, "#2 ds_stack_empty(), wrongly detected empty stack");
			
		ds_stack_clear(stack);
		output = ds_stack_empty(stack);
		assert_true(output, "#3 ds_stack_clear(), failed to clear stack");
			
		ds_stack_destroy(stack);

		// Test v103 deserialisation

		stack = ds_stack_create();
		ds_stack_read(stack, v103_encoded);
						
		output = ds_stack_pop(stack);
		assert_array_equals(output, [ 3.14159, "world" ], "#4.1 ds_stack_read(), failed decoding v103 element (array)");
			
		output = ds_stack_pop(stack);
		assert_equals(output, "hello", "#4.2 ds_stack_read(), failed decoding v103 element (string)");
			
		output = ds_stack_pop(stack);
		assert_equals(output, 200, "#4.3 ds_stack_read(), failed decoding v103 element (real)");
			
		output = ds_stack_pop(stack);
		assert_equals(output, 100, "#4.4 ds_stack_read(), failed decoding v103 element (real)");
			
		output = ds_stack_pop(stack);
		assert_equals(output, 50, "#4.5 ds_stack_read(), failed decoding v103 element (real)");
			
		ds_stack_destroy(stack);


		// Test v102 deserialisation

		stack = ds_stack_create();
		ds_stack_read(stack, v102_encoded);
						
		output = ds_stack_pop(stack);
		assert_equals(output, "world", "#5.1 ds_stack_read(), failed decoding v102 element (string)");
			
		output = ds_stack_pop(stack);
		assert_equals(output, 3.14159, "#5.2 ds_stack_read(), failed decoding v102 element (real)");
			
		output = ds_stack_pop(stack);
		assert_equals(output, "hello", "#5.3 ds_stack_read(), failed decoding v102 element (string)");
			
		output = ds_stack_pop(stack);
		assert_equals(output, 200, "#5.4 ds_stack_read(), failed decoding v102 element (real)");
			
		output = ds_stack_pop(stack);
		assert_equals(output, 100, "#5.5 ds_stack_read(), failed decoding v102 element (real)");
			
		output = ds_stack_pop(stack);
		assert_equals(output, 50, "#5.6 ds_stack_read(), failed decoding v102 element (real)");
			
		ds_stack_destroy(stack);

	})

}

