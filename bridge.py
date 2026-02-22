import os

import numpy as np

import onnxruntime as ort

import onnxruntime_genai as og

from PIL import Image



# --- CONFIGURATION ---

# Paths to your exported ONNX model files and input image

model_dir = "/home/soufiane/Documents/medgemma/medgemma_int4"

img_path = "/home/soufiane/Downloads/y.jpeg"



def sample_top_p(logits, p=0.9, temp=0.8):

"""

Nucleus Sampling (Top-p):

1. Scales logits by temperature to control randomness.

2. Converts logits to a probability distribution (Softmax).

3. Sorts probabilities and keeps only the top cumulative percentage (p).

4. Randomly selects a token from this filtered subset.

"""

logits = logits / temp

probs = np.exp(logits - np.max(logits)) # Numerical stability trick

probs /= np.sum(probs)


sorted_idx = np.argsort(probs)[::-1]

sorted_probs = probs[sorted_idx]

cum_probs = np.cumsum(sorted_probs)


# Identify indices to remove (those exceeding the cumulative p)

idx_to_remove = cum_probs > p

idx_to_remove[1:] = idx_to_remove[:-1].copy()

idx_to_remove[0] = False


probs[sorted_idx[idx_to_remove]] = 0

probs /= np.sum(probs) # Re-normalize

return np.random.choice(len(probs), p=probs)



def run_medgemma_final():

try:

# --- 1. SESSION INITIALIZATION ---

# We initialize 4 separate engines because multimodal ONNX models are

# often split into specialized components for efficiency.

print("🚀 Initializing Engine...")

providers = ['CPUExecutionProvider']



# Vision Encoder: Extracts raw visual features from the pixels

v_sess = ort.InferenceSession(os.path.join(model_dir, "vision_encoder.ort"), providers=providers)

# Vision Projection: Translates visual features into the 'language' (dimension) of the LLM

p_sess = ort.InferenceSession(os.path.join(model_dir, "vision_projection.ort"), providers=providers)

# Embeddings: Converts Token IDs (integers) into dense vectors

e_sess = ort.InferenceSession(os.path.join(model_dir, "embeddings.ort"), providers=providers)

# Main Model: The transformer logic that processes embeddings and predicts the next word

m_sess = ort.InferenceSession(os.path.join(model_dir, "model.onnx"), providers=providers)



# Tokenizer for decoding the integer outputs back into human-readable text

genai_model = og.Model(model_dir)

tokenizer = og.Tokenizer(genai_model)



# Model-specific constants derived from genai_config.json

BOS_ID = 1 # Beginning of Sentence

bos_token = 2 # Secondary BOS used in some Gemma versions

EOT_ID = 106 # End of Turn (stops the model from rambling)

NUM_LAYERS = 34 # Number of Transformer layers (Gemma 2 architecture)

KV_HEADS = 4 # Grouped Query Attention (GQA) Key-Value heads

HEAD_DIM = 256 # Size of each attention head



# --- 2. VISION PROCESSING PHASE ---

print("👁️ Processing X-ray...")

# Load, convert to RGB, and resize to the specific dimensions the encoder expects (896x896)

img = Image.open(img_path).convert('RGB').resize((896, 896), Image.Resampling.BILINEAR)


# Preprocessing: Normalize pixel values from [0, 255] to [-1, 1] range

img_np = (np.array(img).astype(np.float32) / 255.0 - 0.5) / 0.5

# Reshape from (H, W, C) to (Batch, Channel, H, W) for ONNX compatibility

img_np = img_np.transpose(2, 0, 1)[np.newaxis, ...].astype(np.float32)



# Extract features and project them into the LLM's hidden dimension space

vision_raw = v_sess.run(None, {"pixel_values": img_np})[0]

image_features = p_sess.run(None, {p_sess.get_inputs()[0].name: vision_raw})[0]



# --- 3. SEQUENCE ASSEMBLY & EMBEDDING INJECTION ---

print("📝 Preparing Sequence...")

clinical_prompt = """You are a highly experienced Emergency Medicine Physician.

Analyze the following X-ray in detail.

...""" # (Rest of your prompt)



# Identify the ID for the special <image> token used as a placeholder

image_token_id = tokenizer.encode("<image>")[0]



# Build the exact prompt structure MedGemma expects (Jinja Template logic)

user_start_ids = tokenizer.encode("<start_of_turn>user\n").tolist()

model_start_ids = tokenizer.encode("\n<start_of_turn>model\n").tolist()

eot_ids = tokenizer.encode("<end_of_turn>").tolist()


# Construct Token Sequence: [BOS] [User Turn Start] [256 Image Tokens] [Prompt] [End Turn] [Model Start]

image_placeholders = [image_token_id] * 256

prompt_ids = tokenizer.encode(clinical_prompt).tolist()

full_tokens = [bos_token] + user_start_ids + image_placeholders + prompt_ids + eot_ids + model_start_ids


input_ids = np.array([full_tokens], dtype=np.int64)



# Convert all tokens to embeddings via the embedding session

full_embeds = e_sess.run(None, {"input_ids": input_ids})[0]



# THE MAGIC STEP: "Injection"

# We replace the placeholders (nonsense tokens) with the actual projected image features

img_start_idx = len([bos_token]) + len(user_start_ids)

full_embeds[:, img_start_idx : img_start_idx + 256, :] = image_features



# --- 4. AUTOREGRESSIVE GENERATION LOOP ---

print("\n🩺 MedGemma Radiology Report:\n" + "-"*30)



# Initial inputs: the full prompt embeddings and an attention mask of 1s

inputs = {

"inputs_embeds": full_embeds,

"attention_mask": np.ones((1, full_embeds.shape[1]), dtype=np.int64)

}


# Initialize the KV Cache with zeros.

# This cache stores 'keys' and 'values' from previous tokens so the model

# doesn't have to re-process the entire prompt every time it generates a new word.

for i in range(NUM_LAYERS):

inputs[f"past_key_values.{i}.key"] = np.zeros((1, KV_HEADS, 0, HEAD_DIM), dtype=np.float32)

inputs[f"past_key_values.{i}.value"] = np.zeros((1, KV_HEADS, 0, HEAD_DIM), dtype=np.float32)



for _ in range(1024): # Maximum generation limit

# Run the model!

outputs = m_sess.run(None, inputs)

logits = outputs[0]


# Extract the prediction for the very last token in the sequence

next_token_id = sample_top_p(logits[0, -1, :])


# Termination logic: Stop if the model says it's done (EOS or EOT)

if next_token_id in [BOS_ID, EOT_ID]:

break


# Convert ID back to string and print immediately

word = tokenizer.decode([int(next_token_id)])

print(word.replace(' ', ' '), end='', flush=True)


# PREPARE FOR NEXT STEP:

# 1. Get the embedding for JUST the newly generated token

next_embed = e_sess.run(None, {"input_ids": np.array([[next_token_id]], dtype=np.int64)})[0]

inputs["inputs_embeds"] = next_embed

# 2. Expand the attention mask by 1 to account for the new token

inputs["attention_mask"] = np.ones((1, inputs["attention_mask"].shape[1] + 1), dtype=np.int64)

# 3. Update the KV Cache with the values calculated in this step

for j in range(NUM_LAYERS):

# The ONNX model returns new KV pairs starting at index 1 of 'outputs'

inputs[f"past_key_values.{j}.key"] = outputs[1 + j*2]

inputs[f"past_key_values.{j}.value"] = outputs[2 + j*2]



print("\n" + "-"*30)



except Exception as e:

print(f"\n❌ ERROR: {e}")



if __name__ == "__main__":

run_medgemma_final()