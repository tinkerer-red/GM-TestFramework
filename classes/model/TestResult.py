from typing import Optional
import xml.etree.ElementTree as ElementTree

from pydantic import BaseModel

from utils import data_utils

class TestResult(BaseModel):
    name: str = ""
    result: str = ""
    duration: float = 0.0
    assertions: int = 0
    exceptions: Optional[list] = []
    errors: Optional[list[dict]] = []

    def did_error(self):
        return len(self.exceptions) != 0

    def did_expire(self):
        return self.result.lower() == "expired"

    def did_fail(self):
        return self.did_expire() or self.result.lower() == "failed"
    
    def was_skipped(self):
        return self.result.lower() == "skipped"
    
    def to_xml(self) -> ElementTree.Element:
        element = ElementTree.Element('testcase')
        element.set("name", self.name)
        element.set("assertions", str(self.assertions))
        element.set("time", str(self.duration / 1000000))
        
        for exception in self.exceptions:
            exception_element = ElementTree.Element('error')
            exception_element.set("type", "ExceptionThrownError")
            exception_element.text = data_utils.json_stringify(exception)
            element.append(exception_element)
        
        for error in self.errors:
            error_element = ElementTree.Element('failure')
            error_element.set("type", "AssertionError")
            error_element.text = data_utils.json_stringify(error)
            element.append(error_element)
        
        if self.did_expire():
            error_element = ElementTree.Element('failure')
            error_element.set("type", "ExpiredError")
            element.append(error_element)

        if self.was_skipped():
            skipped_element = ElementTree.Element('skipped')
            element.append(skipped_element)


        return element
    
    def to_dict(self) -> dict:
        return {
            'name': self.name,
            'result': self.result,
            'time': self.duration / 1000000,
            'assertions': self.assertions,
            'exceptions': self.exceptions,
            'errors': self.errors,
        }

    def to_summary(self) -> dict:
        summary = {
            'name': self.name,
            **({'errors': [
                    {
                        'expected': error.get('expected'),
                        'actual': error.get('actual'),
                        'description': error.get('description')
                    } for error in self.errors
                ]} if self.errors else {})
        }
        
        if self.exceptions:
            summary['exceptions'] = {
                'count': self.exceptions.count(),
                'first': self.exceptions[0]
            }
        
        return summary