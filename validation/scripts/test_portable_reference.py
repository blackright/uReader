"""Régression du défaut d'oracle : MatMulInteger ne doit pas saturer à 16 bits."""

import unittest

import numpy as np
import onnx
from onnx.reference import ReferenceEvaluator


class PortableReferenceTests(unittest.TestCase):
    def test_products_accumulate_beyond_signed_int16(self):
        graph = onnx.helper.make_graph(
            [onnx.helper.make_node("MatMulInteger", ["a", "b"], ["y"])], "no-int16-saturation",
            [onnx.helper.make_tensor_value_info("a", onnx.TensorProto.UINT8, [1, 2]),
             onnx.helper.make_tensor_value_info("b", onnx.TensorProto.INT8, [2, 1])],
            [onnx.helper.make_tensor_value_info("y", onnx.TensorProto.INT32, [1, 1])])
        model = onnx.helper.make_model(graph, opset_imports=[onnx.helper.make_opsetid("", 10)], ir_version=8)
        reference = ReferenceEvaluator(model)
        for weight, expected in [(127, 64770), (-128, -65280)]:
            output = reference.run(None, {"a": np.array([[255, 255]], np.uint8),
                                         "b": np.array([[weight], [weight]], np.int8)})[0]
            self.assertEqual(output.dtype, np.int32)
            self.assertEqual(output.item(), expected)

    def test_zero_points_are_subtracted_before_matmul(self):
        graph = onnx.helper.make_graph(
            [onnx.helper.make_node("MatMulInteger", ["a", "b", "az", "bz"], ["y"])], "zero-points",
            [onnx.helper.make_tensor_value_info("a", onnx.TensorProto.UINT8, [1, 2]),
             onnx.helper.make_tensor_value_info("b", onnx.TensorProto.INT8, [2, 1]),
             onnx.helper.make_tensor_value_info("az", onnx.TensorProto.UINT8, []),
             onnx.helper.make_tensor_value_info("bz", onnx.TensorProto.INT8, [])],
            [onnx.helper.make_tensor_value_info("y", onnx.TensorProto.INT32, [1, 1])])
        model = onnx.helper.make_model(graph, opset_imports=[onnx.helper.make_opsetid("", 10)], ir_version=8)
        output = ReferenceEvaluator(model).run(None, {
            "a": np.array([[250, 10]], np.uint8), "b": np.array([[120], [-110]], np.int8),
            "az": np.array(128, np.uint8), "bz": np.array(-3, np.int8)})[0]
        self.assertEqual(output.item(), 27632)


if __name__ == "__main__":
    unittest.main()
