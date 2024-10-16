import asyncio
import time
from enum import Enum, auto
from pathlib import Path
from typing import Any, Coroutine, Optional
from xml.etree import ElementTree
from classes.model.TestFrameworkResult import TestFrameworkResult
from classes.model.TestResult import TestResult
from classes.model.TestSuiteResult import TestSuiteResult
from utils import async_utils, data_utils, file_utils, network_utils
from utils.logging_utils import LOGGER
from utils.path_utils import ROOT_DIR

class ExecutionMode(Enum):
    AUTOMATIC = "automatic"
    MANUAL = "manual"

class State(Enum):
    WAITING = auto()
    STARTING = auto()
    RUNNING = auto()
    FINISHED = auto()

class RemoteCommand(Enum):
    GET_TESTS = "TESTS"
    RUN = "RUN {}"  # Placeholder for test path
    EXIT = "EXIT"
    QUIT = "QUIT"

class RemoteControlServer:

    def __init__(self, mode: ExecutionMode, timeout: int = 1, run_name = 'xUnit'):
        """
        Initialize the RemoteControlServer with the given mode.
        
        Args:
            mode (Mode): The mode of operation, either AUTOMATIC or MANUAL.
        """
        self.mode = mode
        self.timeout = timeout
        self.run_name = run_name

        self.tests = []
        self.current_test_index = 0
        self.state = State.WAITING
        self.stop_event = asyncio.Event()
        self.reboot_event = asyncio.Event()
        self.strategy = self._select_strategy()
        
        self.framework_result: TestFrameworkResult = None
        self.suite_results: dict[str, TestSuiteResult] = {}

    def _select_strategy(self) -> Coroutine[Any,Any,None]:
        """
        Select the strategy based on the mode.
        
        Returns:
            Callable: The strategy method to use for handling the client.
        """
        if self.mode == ExecutionMode.AUTOMATIC:
            return self._handle_automatic_mode
        elif self.mode == ExecutionMode.MANUAL:
            return self._handle_manual_mode
        else:
            raise ValueError(f"Unknown mode: {self.mode}")

    def _process_test_result(self, data: str):
        LOGGER.debug("Received test result data")

        try:
            # Parse the incoming data as JSON
            data_json: dict = data_utils.json_parse(data[:-1])

            # Extract necessary fields from the parsed JSON
            result_data: Optional[dict] = data_json.get('details')
            suite: Optional[str] = data_json.get('suite')
            timestamp: Optional[float] = data_json.get('timestamp')

            if result_data is None or suite is None or timestamp is None:
                LOGGER.error("JSON data missing required fields. Skipping processing.")
                return
            
        except KeyError as e:
            LOGGER.error(f"Key error when processing test result: {e}")
        except Exception as e:
            LOGGER.error(f"Unexpected error during processing: {e}", exc_info=True)

        self._add_test_result(result_data, suite, timestamp)

    def _add_test_result(self, result_data: dict, suite: str, timestamp: float):
        # Initialize framework result if not already set
        if not self.framework_result:
            self.framework_result = TestFrameworkResult(name=self.run_name, timestamp=timestamp)
            LOGGER.info(f"Initialized framework result: {self.framework_result.name} at {timestamp}")

        # Initialize suite result or switch to a new suite if necessary
        if not suite in self.suite_results:
            suite_result = TestSuiteResult(name=suite, timestamp=timestamp)
            self.framework_result.testsuites.append(suite_result)
            self.suite_results[suite] = suite_result
            LOGGER.info(f"Initialized new test suite result: {suite} at {timestamp}")

        # Add the test result to the current suite
        result = TestResult(**result_data)
        self.suite_results[suite].tests.append(result)
        LOGGER.debug(f"Added test result: {result_data['name']} with status {result_data['result']}")

    def _inject_dummy_result(self, result = 'failed', duration = 0, assertions = 0, errors:Optional[list] = None, exceptions:Optional[list] = None):
        current_test = self.tests[self.current_test_index]
        suite_name, test_name = current_test.split('@')

        result_data = {
            'name': test_name,
            'result': result,
            'duration': duration,
            'assertions': assertions,
            'errors': errors or [],
            'exceptions': exceptions or []
        }

        self._add_test_result(result_data, suite_name, time.time())

    def _produce_xml_result(self, output_path : Path, filename: str):
        try:
            element = self.framework_result.to_xml()

            # Create an ElementTree object from the root element
            tree = ElementTree.ElementTree(element)

            # Attempt to write the XML file
            xml_file_path = output_path / f'{filename}.xml'
            LOGGER.info(f"Writing XML result to {xml_file_path}")
            tree.write(xml_file_path, encoding='UTF-8', xml_declaration=True)

            LOGGER.info(f"XML result successfully written to {xml_file_path}")

        except ElementTree.ParseError as e:
            LOGGER.error(f"Failed to parse XML structure: {e}")
        except IOError as e:
            LOGGER.error(f"Failed to write XML file to {output_path}. Reason: {e}")
        except Exception as e:
            LOGGER.error(f"An unexpected error occurred: {e}")  

    def _produce_json_result(self, output_path: Path, filename: str):
        try:
            # Construct the JSON file path
            json_file_path = output_path / f'{filename}.json'
            LOGGER.info(f"Writing JSON result to {json_file_path}")

            # Convert the framework result to a dictionary and save it as JSON
            data = self.framework_result.to_dict()
            file_utils.save_data_as_json(data, json_file_path)

            LOGGER.info(f"JSON result successfully written to {json_file_path}")

        except TypeError as e:
            LOGGER.error(f"Failed to serialize data to JSON: {e}")
        except IOError as e:
            LOGGER.error(f"Failed to write JSON file to {json_file_path}. Reason: {e}")
        except Exception as e:
            LOGGER.error(f"An unexpected error occurred while writing JSON file: {e}")

    async def _serve(self, host: str, port: int):
        server = await asyncio.start_server(lambda reader, writer: self._handle_client(reader, writer), host, port)
        addr = server.sockets[0].getsockname()
        LOGGER.info(f'Serving on {addr}')

        await self.stop_event.wait()  # Wait until the stop_event is set
        server.close()
        await server.wait_closed()
        LOGGER.info("Server has stopped.")

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """
        Handle the client connection and delegate to the appropriate strategy.
        """
        addr = writer.get_extra_info('peername')
        LOGGER.info(f"Client connected: {addr}")

        try:
            # Only restore state if mode is AUTOMATIC and state is RUNNING
            if self.mode == ExecutionMode.AUTOMATIC and self.state == State.RUNNING:
                await self._resume_running_tests(reader, writer)
                return  # If state was restored and handled, no need to run the strategy again

            await self.strategy(reader, writer)
        except asyncio.CancelledError:
            LOGGER.info("Connection closed.")
        except ConnectionResetError:
            LOGGER.error("Connection forcibly closed.")
        finally:
            await self._cleanup(writer)

    async def _resume_running_tests(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """
        Resume running tests if the server was in the RUNNING state when the client crashed.
        """
        while self.current_test_index < len(self.tests):
            command = RemoteCommand.RUN.value.format(self.tests[self.current_test_index])
            LOGGER.debug(f"Sending command: {command}")

            if await self._send_command(writer, command):
                LOGGER.warning("Failed to send command, aborting test run.")
                return
            
            data = await self._receive_response(reader)
            if not data:
                self.current_test_index += 1
                LOGGER.warning("No data received, aborting test run.")
                return
            else:
                LOGGER.debug(f"Processing test result for test index {self.current_test_index}")
                self._process_test_result(data)

            self.current_test_index += 1

        if self.current_test_index >= len(self.tests):
            await self._handle_test_execution_finished(writer)

    async def _handle_test_execution_finished(self, writer: asyncio.StreamWriter):
        """
        Handle the actions to be taken once all tests have been executed.
        """
        self.state = State.FINISHED
        LOGGER.info(f"State changed to {self.state}")

        output_path = ROOT_DIR / 'results'
        output_path.mkdir(parents=True, exist_ok=True)

        filename = self.run_name.replace(":", "_")

        LOGGER.debug(f"Producing results files with filename: {filename}")

        try:
            self._produce_xml_result(output_path, filename)
            self._produce_json_result(output_path, filename)
        except Exception as e:
            LOGGER.error(f"Failed to produce result files: {e}")
            self.stop_event.set()  # Signal that the run has finished
            return

        LOGGER.info("All tests executed successfully.")

        await self._send_command(writer, RemoteCommand.EXIT.value)
        LOGGER.info("Sent EXIT command to client.")

        self.stop_event.set()  # Signal that the run has finished
        LOGGER.info("Test run completion signal set.")

    async def _handle_automatic_mode(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter, restore=False):
        """
        Handle client in automatic mode using a state machine.
        """
        if not restore:
            # Transition to STARTING state
            self.state = State.STARTING
            LOGGER.info(f"State changed to {self.state}")

            # Step 1: GET TESTS command
            if await self._send_command(writer, RemoteCommand.GET_TESTS.value):
                return

            received_data = await self._receive_response(reader)
            if not received_data:
                return

            # Update test list
            self.tests = received_data.splitlines()

        # Transition to RUNNING state
        self.state = State.RUNNING
        LOGGER.info(f"State changed to {self.state}")

        # Resume running tests
        await self._resume_running_tests(reader, writer)

    async def _handle_manual_mode(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """
        Handle client in manual mode using a state machine.
        """
        # Transition to RUNNING state (since manual mode starts immediately)
        self.state = State.RUNNING
        LOGGER.info(f"State changed to {self.state}")

        # Immediately set the stop event because manual control is ongoing
        self.stop_event.set()

        while True:
            # Use asyncio to read user input without blocking
            command = input("Enter command and args: ")

            if await self._send_command(writer, command):
                return

            if command.strip().upper() in [RemoteCommand.EXIT.value, RemoteCommand.QUIT.value]:
                LOGGER.info("Waiting for client to disconnect...")
                break

            response = await self._receive_response(reader)
            if not response:
                return
            
            print(f'> {response}')

        # Transition to FINISHED state
        self.state = State.FINISHED
        LOGGER.info(f"State changed to {self.state}")

    async def _send_command(self, writer: asyncio.StreamWriter, command: str) -> bool:
        try:
            writer.write(command.encode() + b'\0')
            await writer.drain()
            LOGGER.debug(f"Sent: {command}")
        except (ConnectionResetError, BrokenPipeError):
            LOGGER.error("Connection lost while sending data to client.")
            return True
        return False

    async def _receive_response(self, reader: asyncio.StreamReader) -> str:
        """
        Receives data from the client and handles possible errors.

        Args:
            reader (asyncio.StreamReader): The stream reader to receive data from.

        Returns:
            str: The received data as a decoded string, or None if an error occurred.
        """
        try:
            data = await asyncio.wait_for(reader.read(8000000), self.timeout * 60)
            if not data:
                LOGGER.info("Client disconnected.")
                return None
            decoded_data = data.decode().strip()
            LOGGER.debug(f"Received: {decoded_data}")
            return decoded_data
        except asyncio.TimeoutError:
            LOGGER.error(f"Client did not respond within {self.timeout} minutes. Killing process.")
            self._inject_dummy_result(result = 'failed', errors= [ { 'message': f'FATAL :: Runner hanged for too long. Process killed.' } ])
            self.reboot_event.set()
            return None
        except ConnectionResetError:
            LOGGER.error("Connection lost while reading data from client.")
            self._inject_dummy_result(result = 'failed', errors= [ { 'message': f'FATAL :: Runner silently crashed.' } ])
            return None

    async def _cleanup(self, writer: asyncio.StreamWriter):
        try:
            writer.close()
            await writer.wait_closed()
        except Exception as e:
            LOGGER.error(f"Error during cleanup: {e}")

    async def serve_or_wait_for_space(self, exe_path, args, port=8000):
        """
        Serve the client or wait for the space key to stop the server.
        """
        local_ip_address = network_utils.get_local_ip()

        await asyncio.gather(
            self._serve(host=local_ip_address, port=port),
            async_utils.wait_for_space_key(self.stop_event),
            async_utils.run_and_monitor_exe(exe_path=exe_path, args=args, stop_event=self.stop_event, reboot_event=self.reboot_event, restart_delay=0.5)
        )

