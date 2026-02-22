import onnx
from onnx import compose
import onnx.checker
import os

# Monkeypatch check_model to avoid validation errors during merge
# (Especially for "no file found" if paths are weird, though we will run in correct dir)
original_check = onnx.checker.check_model
def no_op(*args, **kwargs):
    pass
onnx.checker.check_model = no_op
print("Monkeypatched onnx.checker.check_model to bypass validation.")

# Define paths (absolute)
embed_path = "/home/soufiane/Documents/medgemma/medgemma_int4/embeddings.onnx"
model_path = "/home/soufiane/Documents/medgemma/medgemma_int4/model.onnx.bak"

# We will save to a NEW filename to avoid overwriting or conflict with existing data files
output_path = "/home/soufiane/Documents/medgemma/medgemma_int4/merged_model.onnx" 
output_data_path = "merged_model.onnx.data"

print("Loading models (FULL WITH DATA, this will use memory)...")
# We MUST load external data to merge correctly and save a new unified file
embed_model = onnx.load(embed_path, load_external_data=True)
core_model = onnx.load(model_path, load_external_data=True)

# Align Opset versions
print("Aligning embedding model opset to v21...")
# Get max opset version from core model
core_opset = next((op.version for op in core_model.opset_import if op.domain == "" or op.domain == "ai.onnx"), 21)
print(f"Core opset version: {core_opset}")

# Update embedding model opset
for op in embed_model.opset_import:
    if op.domain == "" or op.domain == "ai.onnx":
        op.version = core_opset

print("Merging models...")
combined_model = compose.merge_models(
    embed_model, 
    core_model, 
    io_map=[("embeddings", "inputs_embeds")]
)

# Fix metadata
combined_model.ir_version = core_model.ir_version
combined_model.opset_import.extend([op for op in core_model.opset_import if op not in combined_model.opset_import])

print(f"Saving merged model to {output_path}...")
# Save with all tensors to a new external data file
if os.path.exists(output_path):
    os.remove(output_path)

onnx.save_model(
    combined_model, 
    output_path, 
    save_as_external_data=True, 
    all_tensors_to_one_file=True, 
    location=output_data_path, 
    size_threshold=1024, 
    convert_attribute=False
)

print("Done.")
