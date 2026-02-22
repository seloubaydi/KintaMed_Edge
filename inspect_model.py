import onnx
import sys

model_path = '/home/soufiane/Documents/medgemma/medgemma_int4/model.onnx'
print(f"Inspecting: {model_path}")

try:
    # Load model structure only (fast)
    model = onnx.load(model_path, load_external_data=False)
    
    print("\n--- Model Inputs ---")
    for input in model.graph.input:
        print(f"Name: {input.name}")
        # print(f"Type: {input.type}") # detailed type info if needed
        
    print("\n--- Model Outputs ---")
    for output in model.graph.output:
        print(f"Name: {output.name}")

except Exception as e:
    print(f"Error loading model: {e}")
