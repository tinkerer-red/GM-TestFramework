

// Generates a random time source configuration, optionally specifying the parent. Returns the configuration.
function GenerateRandomConfiguration(_parent = undefined) constructor
{
	parent = _parent ?? choose(time_source_global, time_source_game);
	period = irandom_range(1, 10); // Integer so we can ignore units
	units = choose(time_source_units_seconds, time_source_units_frames);
	cb = function() {}; // Empty callback
	reps = 1 + irandom(5); // Number of repetitions
	expiryType = choose(time_source_expire_nearest, time_source_expire_after);
}

// Generates a randomly configured time source, optionally specifying the parent. Returns its index.
function generate_time_source(_parent = undefined) 
{
	var _config = new GenerateRandomConfiguration(_parent);
	var _ts = time_source_create(_config.parent, _config.period, _config.units, _config.cb, [], _config.reps, _config.expiryType);
	
	delete _config;
	return _ts;
}

// Generates a struct which holds a time source index and some manually logged parent/child info
function GenerateTreeNode(_parent) constructor
{
	idx = generate_time_source(_parent);
	parent = _parent;
	children = [];
}

// Generates a tree structure of 'tree node' structs generated by GenerateTreeNode
// This is essentially a random node structure with each node holding manually logged info about itself.
function generate_tree(_numSources, _builtInRoot = true) 
{
	var _root, _sources = [];
	
	// Create a '_root' source for the tree
	// This isn't necessarily a built-in (though non built-ins will still have a built-in parent)
	if (_builtInRoot)
	{
		_root = {
			idx: choose(time_source_global, time_source_game),
			parent: undefined,
			children: []
		};
	}
	else 
	{
		var _parent = choose(time_source_global, time_source_game);
		
		_root = {
			idx: generate_time_source(_parent),
			parent: _parent,
			children: []
		}
	}
	
	array_push(_sources, _root);
	
	for (var _i = 0; _i < _numSources; ++_i)
	{
		// Pick a parent source from the already-existing _sources
		var _parent = _sources[irandom(_i)];
		
		// Create a node which is the child of that parent
		var _info = new GenerateTreeNode(_parent.idx);
		
		// Log the child with the parent
		array_push(_parent.children, _info.idx);
		
		// Add the node to a flat array (for simple iteration)
		array_push(_sources, _info);
	}
	
	return _sources;
}

// Cleans up a tree generated by generate_tree
function clean_up_tree(_sources)
{
	for (var _i = array_length(_sources) - 1; _i >= 0; --_i)
	{
		time_source_destroy(_sources[_i].idx); // Intentional attempt to delete a potential built-in at the end
		_sources[_i].children = -1;
		delete _sources[_i];
	}

	_sources = -1;
}


function ResourceTimeSourceTestSuite() : TestSuite() constructor {
	
	var _seed = randomise();
	show_debug_message("Using seed: " + string(_seed));

	addFact("Time Sources: Constant Values", function() {
		
		// Built-in time sources
		assert_equals(time_source_global, 0, "#1 time_source_global, failed to match its built-in value");
	    assert_equals(time_source_game, 1, "#2 time_source_game, failed to match its built-in value");
			
		// Units
	    assert_equals(time_source_units_seconds, 0, "#3 time_source_units_seconds, failed to match its built-in value");
	    assert_equals(time_source_units_frames, 1, "#4 time_source_units_frames, failed to match its built-in value");
			
		// Expiry Types
	    assert_equals(time_source_expire_nearest, 0, "#5 time_source_expire_nearest, failed to match its built-in value");
	    assert_equals(time_source_expire_after, 1, "#6 time_source_expire_after, failed to match its built-in value");
			
		// States
	    assert_equals(time_source_state_initial, 0, "#7 time_source_state_initial, failed to match its built-in value");
	    assert_equals(time_source_state_active, 1, "#8 time_source_state_active, failed to match its built-in value");
	    assert_equals(time_source_state_paused, 2, "#9 time_source_state_paused, failed to match its built-in value");
	    assert_equals(time_source_state_stopped, 3, "#10 time_source_state_stopped, failed to match its built-in value");
	});
		
	addFact("Time Sources: Existence", function() {
		
		var _output;
		
		// Built-in existence
		_output = time_source_exists(time_source_global);
		assert_true(_output, "#1 time_source_exists(), failed to detect built-in source: time_source_global");
			
		_output = time_source_exists(time_source_game);
		assert_true(_output, "#2 time_source_exists(), failed to detect built-in source: time_source_game");
			
		// Built in safety
		time_source_destroy(time_source_global);
		_output = time_source_exists(time_source_global);
		assert_true(_output, "#3 time_source_destroy(), destroyed built-in source: time_source_global (shouldn't)");
			
		time_source_destroy(time_source_game);
		_output = time_source_exists(time_source_game);
		assert_true(_output, "#4 time_source_destroy(), destroyed built-in source: time_source_game (shouldn't)");
			
		// Invalid existence
		_output = time_source_exists(2); // First valid entry
		assert_false(_output, "#5 time_source_exists(), detected a non-existent time source");
			
		// Positive existence
		var _ts = generate_time_source();
		_output = time_source_exists(_ts);
		assert_true(_output, "#6 time_source_create(), failed to create time source");
			
		// Destruction
		time_source_destroy(_ts);
		_output = time_source_exists(_ts);
		assert_false(_output, "#7 time_source_destroy(), failed to destroy time source");	
			
		// Parent safety
		var _ts1 = generate_time_source();
		var _ts2 = generate_time_source(_ts1);
			
		_output = time_source_exists(_ts2);
		assert_true(_output, "#8 time_source_create(), failed to create inherited time source");
			
		time_source_destroy(_ts1); // Can't destroy if it has children
		_output = time_source_exists(_ts1);
		assert_true(_output, "#9 time_source_destroy(), destroyed a source with children (shouldn't)");

		time_source_destroy(_ts2); // Destroy the child
		_output = time_source_exists(_ts2);
		assert_false(_output, "#10 time_source_destroy(), failed to destroy a source with no children");
			
		time_source_destroy(_ts1); // Can destroy it now
		_output = time_source_exists(_ts1);
		assert_false(_output, "#11 time_source_destroy(), failed to destroy a source with no children");
	});

	addFact("Time Sources: State Transitions", function() {				
			
		shift_state = function(_ts) {
			static _current_state = time_source_state_initial;
			
			var _next_state;
			
			while (true) {
				_next_state = choose(time_source_state_initial, time_source_state_active, time_source_state_paused, time_source_state_stopped);
				
				if (_next_state == time_source_state_paused && _current_state != time_source_state_active)
					continue;
				else if (_next_state == time_source_state_stopped && _current_state == time_source_state_initial)
					continue;
				else
					break;
			}
			
			switch(_next_state) {
				case time_source_state_initial:
					time_source_reset(_ts);
					break;
				case time_source_state_active:
					time_source_start(_ts);
					break;	
				case time_source_state_paused:
					time_source_pause(_ts);
					break;	
				case time_source_state_stopped:
					time_source_stop(_ts);
					break;	
			}
			
			check_state(_ts, _next_state);
			_current_state = _next_state;
		}
				
		// Checks a time source's and all of its descendants' states
		check_state = function(_ts, _state) {
				
			var _output = time_source_get_state(_ts);
			assert_equals(_output, _state, "time_source_set/get_state, mismatch state values");
					
			var _children = time_source_get_children(_ts);
					
			for (var _i = 0; _i < array_length(_children); ++_i)
			{
				check_state(_children[_i], _state);	
			}
		}
				
		var _num_shifts = 1000;
		var _num_sources = 10;
			
		// Create a small tree of sources with a non built-in root
		var _nodes = generate_tree(_num_sources, false);
		var _root_ts = _nodes[0].idx;
				
		for (var _i = 0; _i < _num_shifts; ++_i)
		{
			shift_state(_root_ts); // Shift and check the sources' states
		}
				
		clean_up_tree(_nodes);
	}, { test_filter: platform_noone });
	
	addFact("Time Sources: Parents and Children", function() {
			
		var _numSources = 100;
				
		// Create a tree structure
		var _nodes = generate_tree(_numSources);
			
		var _output;
			
		// Check that each source's parent and children are what we expect
		for (var _i = _numSources; _i >= 0; --_i)
		{
			var _ts = _nodes[_i].idx;

			_output = time_source_get_parent(_ts)
			assert_equals(_output, _nodes[_i].parent, "time_source_get_parent(), failed to retrieve the correct parent");
				
			_output = time_source_get_children(_ts);
			assert_array_length(_output, array_length(_nodes[_i].children), "time_source_get_children(), failed to return the correct number of children");
				
			assert_array_equals(_output, _nodes[_i].children, "time_source_get_children(), failed to return the correct children data");
		}
				
		clean_up_tree(_nodes);
	});
	
	addFact("Time Sources: Reconfiguration", function() { 
		var _numConfigurations = 1000;
								
		var _output, _ts = generate_time_source();
				
		for (var _i = 0; _i < _numConfigurations; ++_i)
		{
			var _config = new GenerateRandomConfiguration();
			time_source_reconfigure(_ts, _config.period, _config.units, _config.cb, [], _config.reps, _config.expiryType);
				
			_output = time_source_get_period(_ts);
			assert_equals(_output, _config.period, "time_source_reconfigure(), failed to reset the period");
				
			_output = time_source_get_time_remaining(_ts);
			assert_equals(_output, _config.period, "time_source_reconfigure(), failed to reset the time remaining");
				
			_output = time_source_get_reps_completed(_ts);
			assert_equals(_output, 0, "time_source_reconfigure(), failed to reset the completed repetitions");
				
			_output = time_source_get_reps_remaining(_ts);
			assert_equals(_output, _config.reps, "time_source_reconfigure(), failed to reset the remaining repetitions");
				
			_output = time_source_get_units(_ts);
			assert_equals(_output, _config.units, "time_source_reconfigure(), failed to reset the units");
					
			delete _config;
		}
		
		time_source_destroy(_ts);
		
	}, { test_filter: platform_noone });
	
	addTestAsync("Time Sources: Expiry Frames", objTestAsync, {
	
		ev_create: function() {
						
			oldSpeed = game_get_speed(gamespeed_fps);
			
			// Set the game frame rate to a fixed, known value so that we can roughly estimate expected expiry frames
			gamespeed = irandom_range(10, 100);
			game_set_speed(gamespeed, gamespeed_fps);

			numTests = 10; // The number of time sources to create
			maxPeriodSecs = 1; // Maximum source period (in seconds)
			maxPeriodFrames = maxPeriodSecs * gamespeed; // Maximum source period (in frames)
			maxRepeats = 4; // Maximum reps a source will perform
			maxTestDurFrames = maxPeriodFrames * maxRepeats; // Maximum duration of the test

			cb = function() {} // Empty callback function

			// As we don't have access to the microsecond timer resolution here as well as the true frame-to-frame time deltas,
			// it is impossible to accurately predict expiry frames in all cases.
			// Allow a 1 frame difference in expiry from the expected frame (in either direction)
			tolerance = 1;

			// This generates random time source configurations, with a calculated expiry frame
			function generateRandomConfigWithExpiryFrame(_gameSpeed, _maxPeriodSecs, _maxPeriodFrames, _maxRepeats) constructor
			{
				parent = choose(time_source_global, time_source_game);
				units = choose(time_source_units_seconds, time_source_units_frames);
				reps = 1 + irandom(_maxRepeats); // Number of repetitions
				expiryType = choose(time_source_expire_nearest, time_source_expire_after);

				if (units == time_source_units_seconds)
				{
					roundTo = function(_n, _resolution) {
						var _r = 1 / _resolution;
						return ceil(_n * _r) / _r;
					}
		
					// Set a minimum period of a frame's period
					var _minPeriodSecs = 1 / _gameSpeed;
		
					// Force a maximum resolution of 0.01s for ease of debugging
					period = roundTo(max(_minPeriodSecs, random(_maxPeriodSecs)), 0.01);
		
					// Calculate the expected expiry frame (fractional)
					var _expiryFrame = _gameSpeed * period * (reps + 1);

					if (expiryType == time_source_expire_nearest)
					{
						var _expiryFrameRounded;
			
						// Round for 'nearest' expiry type
						// Can't use the 'round' function because it uses bankers rounding...
						if (frac(_expiryFrame) >= 0.5)
						{
							_expiryFrameRounded = ceil(_expiryFrame);
						}
						else 
						{
							_expiryFrameRounded = floor(_expiryFrame);
						}
			
						expectedExpiryFrame = max(1, _expiryFrameRounded);
					}
					else // eTimeSourceExpiry_After
					{
						// Round up for 'after' expiry type
						expectedExpiryFrame = max(1, ceil(_expiryFrame));
					}
				}
				else
				{
					period = max(1, irandom(_maxPeriodFrames));
					expectedExpiryFrame = period * reps;
				}
			}

			configs = [] // Time source configs
			sources = [] // Time source indexes

			for (var _i = 0; _i < numTests; ++_i)
			{
				// Generate a load of test sources
				configs[_i] = new generateRandomConfigWithExpiryFrame(gamespeed, maxPeriodSecs, maxPeriodFrames, maxRepeats);
				sources[_i] = time_source_create(configs[_i].parent, configs[_i].period, configs[_i].units, cb, [], configs[_i].reps, configs[_i].expiryType);

				time_source_start(sources[_i]);
			}

			frameCounter = 0; // Counts frames
			
		},
			
		ev_step: function() {
			
			++frameCounter;

			for (var _i = 0; _i < numTests; ++_i)
			{
				var _config = configs[_i];
				var _source = sources[_i];
				
				// If we're not in the source's tolerance zone (only applies to sources measured in seconds)
				if (abs(frameCounter - _config.expectedExpiryFrame) > tolerance
				&& (_config.units == time_source_units_seconds))
				{
					
					var _state = time_source_get_state(_source);
					
					// Check that the time source is active before its expiry frame
					if (frameCounter < _config.expectedExpiryFrame) {
						
						if (!assert_equals(_state, time_source_state_active, "Source #" + string(_i) + " failed condition #1 (inactive too early).")) {	
							
							show_debug_message("Current frame: " + string(frameCounter));
							show_debug_message("Expected expiry frame: " + string(_config.expectedExpiryFrame));
							show_debug_message("Tolerance: " + string(tolerance));
							show_debug_message("State: " + string(time_source_get_state(_source)));
							
							return test_end();
						}
					}
					// Check that the time source is inactive on or after its expiry frame
					else {
						
						if (!assert_equals(_state, time_source_state_initial, "Source #" + string(_i) + " failed condition #2 (active too late).")) {	
		
							show_debug_message("Current frame: " + string(frameCounter));
							show_debug_message("Expected expiry frame: " + string(_config.expectedExpiryFrame));
							show_debug_message("Tolerance: " + string(tolerance));
							show_debug_message("State: " + string(time_source_get_state(_source)));
							
							return test_end();
						}	
					}
					
					return test_end();
				}
			}

			show_debug_message("{0}/{1}", frameCounter, maxPeriodFrames);

			// If we've not failed after our imposed frame limit
			if (frameCounter > maxTestDurFrames) {
				
				show_debug_message("Test Ended Successfully");
				
				return test_end();
			}
				
		},
		
		ev_cleanup: function() {
			
			// Destroy all the time sources
			for (var _i = 0; _i < numTests; ++_i)
			{
				delete configs[_i];
				time_source_destroy(sources[_i]);
			}
			
			// Reset to unbounded frame rate
			game_set_speed(oldSpeed, gamespeed_fps);
		}
	
	});

	addTestAsync("Time Sources: Self Destruction", objTestAsync, {
	
		// In this test we want to make sure that a time source can destroy itself in its own callback
		// We also want to make sure that it is considered destroyed as soon as time_source_destroy has been called
		ev_create: function() {

			callbackFinished = false;
			frameCounter = -1;
			
			var _callback = function() {
				// Record the expiry frame
				expiryFrame = frameCounter;
				
				// Make sure the source still exists
				assert_equals(time_source_exists(ts), true, "Time source does not appear to exist before its self-destruction");
				
				// Self-destruct
				time_source_destroy(ts);
				
				// As soon as time_source_destroy is called successfully, it should be considered destroyed.
				// (Though it does secretly continue to exist until the callback returns)
				assert_equals(time_source_exists(ts), false, "Time source still appears to exist after its self-destruction");

				// Indicate that we should now independently check existence
				callbackFinished = true;
			}
			
			var _parent = choose(time_source_global, time_source_game);
			var _period = irandom_range(5, 20);
			
			ts = time_source_create(_parent, _period, time_source_units_frames, _callback);
			time_source_start(ts);
		},
		
		ev_step: function() {
			// If the source has expired
			if (callbackFinished)
			{
				// Check that we are on the same frame as the callback invocation
				assert_equals(expiryFrame, frameCounter, "Time source did not appear to be destroyed on the same frame as its self-destruction");
				
				// Check again that it doesn't exist
				assert_not_equals(time_source_exists(ts), true, "Time source still appears to exist after its self-destruction");
				
				show_debug_message("Test completed successfully");
				
				test_end();
			}
			
			++frameCounter;
		},
		
		ev_cleanup: function() {
			if (time_source_exists(ts))
			{
				time_source_destroy(ts);	
			}
		}
	
	});
				
	addTestAsync("Time Sources: Sibling Destruction", objTestAsync, {
	
		// In this test we want to check that the array mutation (in the runner) caused by time sources
		// destroying themselves or their siblings does not lead to any errors or crashes.
		ev_create: function() {
			
			// Frame counter
			frameCounter = -1;
			
			// All siblings should share the same parent
			parent = choose(time_source_global, time_source_game);
			
			// They should all execute their callbacks on the same frame as well
			period = irandom_range(5, 20);
			
			var _callback = function() {
				// Get the remaining siblings
				var _siblings = time_source_get_children(parent);
				
				// Pick one - it could be itself but we should be checking that as well
				var _idx = irandom_range(0, array_length(_siblings) - 1);
				
				// Destroy it
				time_source_destroy(_siblings[_idx]);
			}
			
			// We want this to be reasonably large
			numSources = 100;
			
			for (var _i = 0; _i < numSources; ++_i)
			{
				ts = time_source_create(parent, period, time_source_units_frames, _callback);
				time_source_start(ts);
			}
		},
		
		ev_step: function() {		
			++frameCounter;
			
			// Callbacks should have been executed
			if (frameCounter == period)
			{
				var _sources = time_source_get_children(parent);
				var _numRemaining = array_length(_sources);
					
				// If sources have been successfully destroying one another
				// we should have fewer than we started with (but not necessarily zero)
				assert_less(_numRemaining, numSources, "Error: No sources were destroyed");

				show_debug_message("Test completed successfully");
				test_end();
			}
		},
		
		ev_cleanup: function() {
			// Destroy any sources left behind
			var _sources = time_source_get_children(parent);
			
			for (var _i = 0; _i < array_length(_sources); ++_i)
			{
				time_source_destroy(_sources[_i]);	
			}
		}
	
	}, { test_filter: platform_noone });
	
	addTestAsync("Time Sources: Time delta propagation", objTestAsync, {
	
		// In this test we want to make sure that time deltas propagate to all sources before any callbacks are invoked.
		// We can do this by having a callback from a global source create a new game source (game sources are processed after global sources)
		// and then make sure that the remaining time isn't decremented for that new game source.
		ev_create: function() {
			
			firstCallbackFinished = false;

			// Setup a new time source to expire on the next frame
			var _callback = function() {
				// We shouldn't see this execute unless time deltas propagated after the first callback was invoked
				var _callback2 = function() {
					assert_true(false, "Second callback should not have been executed");
					test_end();
				}
				
				ts2 = time_source_create(time_source_game, 1, time_source_units_frames, _callback2);
				time_source_start(ts2);
				firstCallbackFinished = true;
			}
			
			ts1 = time_source_create(time_source_global, irandom_range(5, 10), time_source_units_frames, _callback);
			time_source_start(ts1);
		},
		
		ev_step: function() {
			// If the first callback has finished, the second time source should have been set up, but should not have been ticked
			if (firstCallbackFinished)
			{
				if (assert_equals(time_source_get_time_remaining(ts2), 1, "Second time source showed incorrect remaining time")) {
					test_end();
				}
				else test_end();
				
				show_debug_message("Test completed successfully");
			}
		},
		
		ev_cleanup: function() {
			
			time_source_destroy(ts1);
			time_source_destroy(ts2);
		}
	
	});
}

