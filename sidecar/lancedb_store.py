import lancedb
import os
from pydantic import BaseModel
from typing import List, Optional, Dict
import time
from fastembed import TextEmbedding
import numpy as np
import uuid

# Use a local data directory for the DB
DB_PATH = os.path.join(os.getcwd(), "data", "clippy-lancedb")

class ClipboardItem(BaseModel):
    id: str
    text_content: str
    timestamp: float
    source_app: str
    tags: List[str]
    vector: Optional[List[float]] = None

class LanceDBStore:
    def __init__(self):
        print("Initializing LanceDB Store...")
        os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
        self.db = lancedb.connect(DB_PATH)
        self.table_name = "clipboard_memory"
        
        # Initialize embedding model
        # lightweight model for local usage
        self.embedding_model = TextEmbedding(model_name="BAAI/bge-small-en-v1.5")
        
        self._init_table()

    def _init_table(self):
        # Create table if not exists
        if self.table_name not in self.db.table_names():
            # Define schema by adding a dummy item
            # We'll use a fixed size vector for bge-small-en-v1.5 which is 384 dim
            dummy_vector = [0.0] * 384 
            schema_data = [{
                "id": "init", 
                "text_content": "init", 
                "timestamp": 0.0, 
                "source_app": "init", 
                "tags": ["init"],
                "vector": dummy_vector
            }]
            self.db.create_table(self.table_name, data=schema_data, mode="overwrite")
            print(f"Created table {self.table_name}")
        else:
            print(f"Table {self.table_name} exists")

    def _embed(self, text: str) -> List[float]:
        # Generator returns list of vectors, we take the first one
        embeddings = list(self.embedding_model.embed([text]))
        return embeddings[0].tolist()

    def add_item(self, text: str, source_app: str, tags: List[str] = []) -> str:
        vector = self._embed(text)
        item_id = str(uuid.uuid4())
        
        item = {
            "id": item_id,
            "text_content": text,
            "timestamp": time.time(),
            "source_app": source_app,
            "tags": tags,
            "vector": vector
        }
        
        tbl = self.db.open_table(self.table_name)
        tbl.add([item])
        print(f"Added item {item_id} to LanceDB")
        return item_id
        
    def search(self, query: str, limit: int = 5) -> List[Dict]:
        query_vector = self._embed(query)
        
        tbl = self.db.open_table(self.table_name)
        
        # LanceDB search API
        results = tbl.search(query_vector).limit(limit).to_list()
        
        # Filter out the init dummy item if present (though unlikely to be top match)
        cleaned_results = [r for r in results if r['id'] != 'init']
        
        return cleaned_results

# Singleton instance
store = LanceDBStore()
