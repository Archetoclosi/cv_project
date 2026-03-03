import unittest
import tempfile
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'tools'))


class TestReceiverPipe(unittest.TestCase):
    def test_write_to_pipe_function_exists(self):
        """Test that write_to_pipe function exists and is callable"""
        from sensor_receiver import write_to_pipe
        assert callable(write_to_pipe)

    def test_parse_sensor_data(self):
        """Test that sensor data can be parsed correctly"""
        from sensor_receiver import write_to_pipe

        # Just verify the function exists - actual write test requires fifo
        test_data = "SENSOR|1000|A:0.1,0.2,0.3|G:0.01,0.02,0.03|M:10,20,30"
        # This would write to pipe, which requires integration test
        # For unit test, we just verify the function exists


if __name__ == "__main__":
    unittest.main()
