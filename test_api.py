import os
from inceptionai import Inception

client = Inception(
    api_key=os.environ.get("INCEPTION_API_KEY"),
)

chat_completion = client.chat.completions.create(
    model="mercury-2.5",
    messages=[
        {
            "role": "user",
            "content": "What is a diffusion language model?"
        }
    ],
    max_tokens=256,
    temperature=0.75,
)
print(chat_completion)
