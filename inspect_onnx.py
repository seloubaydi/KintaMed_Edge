import onnx

def inspect(path):
    print(f"\n--- Inputs for {path} ---")
    try:
        # Load only the model proto without external data
        model = onnx.load(path, load_external_data=False)
        for input in model.graph.input:
            # Print name and type info if available
            print(f"  - {input.name}")
    except Exception as e:
        print(f"  Error: {e}")

inspect("/home/soufiane/Documents/medgemma/medgemma_int4/model.onnx")
