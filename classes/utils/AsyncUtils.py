import asyncio
import logging
import sys
from typing import Optional

from classes.utils.LoggingUtils import LoggingUtils

class AsyncUtils:

    @staticmethod
    async def _run_exe_base(exe_path: str, args: list[str]) -> asyncio.subprocess.Process:
        # Start the subprocess
        process = await asyncio.create_subprocess_exec(
            exe_path,
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT
        )
        return process
    
    @staticmethod
    async def _capture_output(process: asyncio.subprocess.Process):
        
        stdout_output = ''

        # Don't print the level in the logger for this function
        LoggingUtils.config_logger(format='%(asctime)s %(message)s')
        
        # Read output line by line as it becomes available
        while True:
            stdout_line = await process.stdout.readline()
            if not stdout_line:
                break
            stripped_output = stdout_line.decode('utf-8').strip()
            if stripped_output != '':
                stdout_output += stripped_output + '\n'
                logging.info(stripped_output)

        # Return logger to default configuration if needed
        LoggingUtils.config_logger()

        return stdout_output
    
    @staticmethod
    async def run_exe_and_capture(exe_path: str, args: list[str]):
        logging.info(f'Running {exe_path} with arguments {args}')
        
        # Start the subprocess
        process = await AsyncUtils._run_exe_base(exe_path, args)
        
        stdout_output = await AsyncUtils._capture_output(process)
        
        await process.wait()  # Wait for the subprocess to exit

        logging.info(f'Process completed')
        return stdout_output

    @staticmethod
    async def _handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, process: asyncio.subprocess.Process, stop_event: asyncio.Event, timeout: int):
        """
        Handles communication with a single connected client.
        """
        addr = writer.get_extra_info('peername')
        print(f"Client connected: {addr}")
        
        try:
            while True:
                command = input("Enter command and args: ")

                writer.write(command.encode() + b'\0')
                await writer.drain()
                logging.info(f"Sent: {command}")
                
                if command.strip().lower() in ['exit', 'quit']:
                    logging.info("Waiting for client to disconnect...")
                    await writer.drain()
                    break

                try:
                    data = await asyncio.wait_for(reader.read(1024), timeout=timeout * 60)
                except asyncio.TimeoutError:
                    if process:
                        logging.error(f"Client did not respond within {timeout} minutes. Killing process.")
                        if process:
                            process.kill()
                    break

                if not data:
                    logging.info("Client disconnected.")
                    break
                logging.info(f"Received: {data.decode().strip()}")

        except asyncio.CancelledError:
            logging.info("Connection closed.")
        except ConnectionResetError:
            logging.error(f"Connection forcibly closed.")
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass
            stop_event.set()
    
    @staticmethod
    async def serve(process: asyncio.subprocess.Process, host: str, port: int, timeout: int, stop_event: Optional[asyncio.Event] = None):

        if stop_event == None:
            stop_event = asyncio.Event()

        server = await asyncio.start_server(lambda r, w: AsyncUtils._handle_client(r, w, process, stop_event, timeout), host, port)
        addr = server.sockets[0].getsockname()
        logging.info(f'Serving on {addr}')

        await stop_event.wait()  # Wait until the client disconnects
        server.close()
        await server.wait_closed()

        logging.info("Server has stopped.")

    @staticmethod
    async def run_exe_and_serve(exe_path: str, args: list[str], host: str = '127.0.0.1', port: int = 8000, timeout: int = 2):
        logging.info(f'Running {exe_path} with arguments {args}')

        # Start the subprocess
        process = await AsyncUtils._run_exe_base(exe_path, args)

        stop_event = asyncio.Event()

        await AsyncUtils.serve(process, host, port, timeout, stop_event)

        await process.wait()  # Wait for the subprocess to exit
        logging.info(f'Process completed')

    @staticmethod
    async def run_exe_serve_and_capture(exe_path: str, args: list[str], host: str ='127.0.0.1', port: int = 8000, timeout: int = 2):
        """
        Runs an executable, serves it over TCP, and captures the output.
        """
        logging.info(f'Running {exe_path} with arguments {args}')

        # Start the subprocess
        process = await AsyncUtils._run_exe_base(exe_path, args)

        stop_event = asyncio.Event()

        # Capture output concurrently while serving the client
        await asyncio.gather(
            AsyncUtils.serve(process, host, port, timeout, stop_event),
            AsyncUtils._capture_output(process)
        )

        await process.wait()  # Wait for the subprocess to exit
        logging.info(f'Process completed')

    @staticmethod
    async def wait_for_space_key(stop_event: Optional[asyncio.Event] = None):

        if stop_event == None:
            stop_event = asyncio.Event()

        async def check_keypress_unix():
            import termios, tty
            fd = sys.stdin.fileno()
            old_settings = termios.tcgetattr(fd)
            try:
                tty.setcbreak(fd)
                loop = asyncio.get_running_loop()
                while True:
                    if stop_event.is_set():
                        break
                    # Wait for input to be available
                    await loop.run_in_executor(None, sys.stdin.read, 1)
                    if sys.stdin.read(1) == ' ':
                        print("Space key pressed. Stopping server.")
                        stop_event.set()
                        break
            finally:
                termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

        async def check_keypress_win():
            import msvcrt
            while True:
                if stop_event.is_set():
                    break
                await asyncio.sleep(0.1)  # Small delay to yield control
                if msvcrt.kbhit() and msvcrt.getch() == b' ':
                    print("Space key pressed. Stopping server.")
                    stop_event.set()
                    break

        print("Press the space key to stop the server...")
        if sys.platform == 'win32':
            await check_keypress_win()
        else:
            await check_keypress_unix()

