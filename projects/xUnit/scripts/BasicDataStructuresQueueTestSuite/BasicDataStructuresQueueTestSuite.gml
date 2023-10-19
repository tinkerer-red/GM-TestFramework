

function BasicDataStructuresQueueTestSuite() : TestSuite() constructor {

	addFact("ds_queue_create_test", function() {		
			
		var queue = ds_queue_create();
			
		var output = ds_exists(queue, ds_type_queue);
		assert_true(output, "#1 ds_queue_create(), failed to create queue");
			
		ds_queue_destroy(queue);
			
	})

	addFact("ds_queue_enqueue_dequeue_test", function() {
			
		var queue, output;
			
		queue = ds_queue_create();
		ds_queue_enqueue(queue, 100, 200, 300);
			
		assert_queue_size(queue, 3, "#1 ds_queue_enqueue(...), failed to enqueue the correct number of arguments");
			
		output = ds_queue_dequeue(queue);
		assert_equals(output, 100, "#2.1 ds_queue_dequeue(...), failed to dequeue correct element from queue");
		assert_queue_size(queue, 2, "#2.2 ds_queue_dequeue(...), failed to resize the queue");
			
		ds_queue_dequeue(queue);
			
		output = ds_queue_dequeue(queue);
		assert_equals(output, 300, "#3 ds_queue_dequeue(...), failed to dequeue correct element from queue");
			
		output = ds_queue_empty(queue);
		assert_true(output, "#4 ds_queue_empty(...), failed identify empty queue");
			
		output = ds_queue_dequeue(queue);
		assert_equals(output, undefined, "#4 ds_queue_dequeue(...), dequeuing from empty queue should return 'undefined'");
			
		ds_queue_destroy(queue);
	})

	addFact("ds_queue_head_tail_test", function() {

		var queue, output;

		queue = ds_queue_create();
		ds_queue_enqueue(queue, 100, 200, 300);

		output = ds_queue_head(queue);
		assert_equals(output, 100, "#1 ds_queue_head(), failed to correctly identify the head of the queue");

		output = ds_queue_tail(queue);
		assert_equals(output, 300, "#1 ds_queue_tail(), failed to correctly identify the tail of the queue");

		ds_queue_destroy(queue);
			
	})

	addFact("ds_queue_copy_test", function() {
			
		var queue, copiedQueue;
			
		queue = ds_queue_create();
		ds_queue_enqueue(queue, 100, 200, 300);

		copiedQueue = ds_queue_create();
		ds_queue_copy(copiedQueue, queue);
			
		assert_queue_equals(queue, copiedQueue, "#1 ds_queue_copy, failed to correctly copy a queue");
			
		ds_queue_destroy(queue);
		ds_queue_destroy(copiedQueue);
	})

	addFact("ds_queue_read_write_test", function() {
			
		var queue, output, writtenQueue;
			
		queue = ds_queue_create();
		ds_queue_enqueue(queue, 100, 200, 300);
			
		writtenQueue = ds_queue_write(queue);
			
		var checkNative = "CB000000030000000000000010000000000000000000000000005940000000000000000000006940000000000000000000C07240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
		var checkBrowser = "CB000000030000000000000003000000000000000000000000005940000000000000000000006940000000000000000000C07240";
			
		// RK :: browser does not have compatible read write strings with Native
		var checkValue = (os_browser == browser_not_a_browser) ? checkNative : checkBrowser;
		assert_equals(writtenQueue, checkValue, "#1 ds_queue_write(), doesn't match pre-baked encoded string");
			
		ds_queue_clear(queue);
		assert_queue_empty(queue, "#2 ds_queue_clear(), failed to clear the queue");
			
		ds_queue_read(queue, writtenQueue);
		assert_queue_size(queue, 3, "#3.1 ds_queue_read(), failed to load the correct number of elements");
		assert_queue_equals_array(queue, [100, 200, 300], "#3.2 ds_queue_read(), failed to load the correct data");
			
		ds_queue_destroy(queue);
	})
	
}