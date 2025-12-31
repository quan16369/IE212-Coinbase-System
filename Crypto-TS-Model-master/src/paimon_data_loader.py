# Data loader with Paimon integration

import pandas as pd
import numpy as np
import torch
from torch.utils.data import Dataset, DataLoader
from typing import Tuple, List
import logging

logger = logging.getLogger(__name__)


class PaimonDataLoader:
    """
    Data loader that reads from Apache Paimon lakehouse
    
    Benefits:
    - Unified batch and streaming data access
    - Time travel queries for reproducible training
    - ACID transactions
    - Better compression
    """
    
    def __init__(self, warehouse_path: str, table_name: str):
        from pyspark.sql import SparkSession
        
        self.warehouse_path = warehouse_path
        self.table_name = table_name
        
        # Initialize Spark with Paimon
        self.spark = SparkSession.builder \
            .appName("CryptoModelDataLoader") \
            .config("spark.sql.catalog.paimon", "org.apache.paimon.spark.SparkCatalog") \
            .config("spark.sql.catalog.paimon.warehouse", warehouse_path) \
            .getOrCreate()
        
        logger.info(f"Initialized Paimon data loader for {table_name}")
    
    def load_data(self, start_date: str = None, end_date: str = None, 
                  product_id: str = "BTC-USD") -> pd.DataFrame:
        """
        Load data from Paimon table
        
        Args:
            start_date: Start date (YYYY-MM-DD)
            end_date: End date (YYYY-MM-DD)
            product_id: Product ID to filter
        
        Returns:
            DataFrame with features
        """
        query = f"SELECT * FROM paimon.{self.table_name} WHERE product_id = '{product_id}'"
        
        if start_date and end_date:
            query += f" AND dt >= '{start_date}' AND dt <= '{end_date}'"
        
        query += " ORDER BY timestamp"
        
        df = self.spark.sql(query).toPandas()
        logger.info(f"Loaded {len(df)} rows from Paimon")
        
        return df
    
    def get_loaders(self, batch_size: int = 64, num_workers: int = 4,
                   train_ratio: float = 0.8, val_ratio: float = 0.1) -> Tuple[DataLoader, DataLoader, DataLoader]:
        """
        Get train/val/test data loaders
        
        Returns:
            Tuple of (train_loader, val_loader, test_loader)
        """
        # Load data
        df = self.load_data()
        
        # Prepare features
        feature_cols = ['close', 'volume', 'rsi_14', 'macd', 'bb_middle', 'atr_14']
        df = df[feature_cols].fillna(method='ffill')
        
        # Split data
        n = len(df)
        train_end = int(n * train_ratio)
        val_end = int(n * (train_ratio + val_ratio))
        
        train_data = df[:train_end].values
        val_data = df[train_end:val_end].values
        test_data = df[val_end:].values
        
        # Create datasets
        train_dataset = TimeSeriesDataset(train_data, seq_len=288, pred_len=12)
        val_dataset = TimeSeriesDataset(val_data, seq_len=288, pred_len=12)
        test_dataset = TimeSeriesDataset(test_data, seq_len=288, pred_len=12)
        
        # Create data loaders
        train_loader = DataLoader(train_dataset, batch_size=batch_size, 
                                 shuffle=True, num_workers=num_workers)
        val_loader = DataLoader(val_dataset, batch_size=batch_size, 
                               shuffle=False, num_workers=num_workers)
        test_loader = DataLoader(test_dataset, batch_size=batch_size, 
                                shuffle=False, num_workers=num_workers)
        
        logger.info(f"Created data loaders: train={len(train_dataset)}, "
                   f"val={len(val_dataset)}, test={len(test_dataset)}")
        
        return train_loader, val_loader, test_loader


class TimeSeriesDataset(Dataset):
    """Time series dataset for sliding window approach"""
    
    def __init__(self, data: np.ndarray, seq_len: int = 288, pred_len: int = 12):
        self.data = data
        self.seq_len = seq_len
        self.pred_len = pred_len
    
    def __len__(self):
        return len(self.data) - self.seq_len - self.pred_len + 1
    
    def __getitem__(self, idx):
        # Input sequence
        x = self.data[idx:idx + self.seq_len]
        
        # Target (predict next pred_len steps)
        y = self.data[idx + self.seq_len:idx + self.seq_len + self.pred_len, 0]  # Only close price
        
        return torch.FloatTensor(x), torch.FloatTensor(y)


if __name__ == "__main__":
    # Test data loader
    loader = PaimonDataLoader(
        warehouse_path="s3a://crypto-pipeline-data-lake/paimon",
        table_name="crypto_db.ml_features"
    )
    
    train_loader, val_loader, test_loader = loader.get_loaders()
    
    # Test batch
    for batch_x, batch_y in train_loader:
        print(f"Input shape: {batch_x.shape}")
        print(f"Target shape: {batch_y.shape}")
        break
