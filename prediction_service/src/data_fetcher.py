import logging
import pandas as pd
import numpy as np
from typing import List, Dict, Optional, Tuple
from datetime import datetime, timedelta
from cassandra_client import CassandraClient
import sys
from pathlib import Path

# Import CryptoDataset class to reuse data processing functions
current_dir = Path(__file__).parent
model_src_path = current_dir.parent / 'model' / 'src'
sys.path.append(str(model_src_path))

from data_loader import CryptoDataset

logger = logging.getLogger(__name__)

class CryptoDataFetcher:
    """Fetch and process Cassandra data for prediction by reusing CryptoDataset."""
    
    def __init__(self, cassandra_client: CassandraClient):
        self.client = cassandra_client
        self.session = cassandra_client.get_session()
        
        # Prepare statements for better performance
        self._prepare_statements()
    
    def _prepare_statements(self):
        """Prepare common queries."""
        self.get_candles_stmt = self.session.prepare("""
            SELECT product_id, start_time, open, high, low, close, volume
            FROM candles 
            WHERE product_id = ? AND start_time >= ? AND start_time <= ?
            ORDER BY start_time ASC
        """)
        
        self.get_latest_candles_stmt = self.session.prepare("""
            SELECT product_id, start_time, open, high, low, close, volume
            FROM candles 
            WHERE product_id = ? AND start_time >= ?
            ORDER BY start_time DESC
            LIMIT ?
        """)
    
    def fetch_ohlcv_data(self, 
                        product_id: str, 
                        start_time: datetime, 
                        end_time: datetime = None,
                        limit: int = None) -> pd.DataFrame:
        """
        Fetch OHLCV data from Cassandra and format it like the training data.
        
        Args:
            product_id: Product ID (for example: BTC-USD)
            start_time: Start time
            end_time: End time (None = current time)
            limit: Record limit (None = unlimited)
        
        Returns:
            DataFrame with format: timestamp, Open, High, Low, Close, Volume
        """
        try:
            if end_time is None:
                end_time = datetime.utcnow()
            
            if limit:
                rows = self.session.execute(
                    self.get_latest_candles_stmt,
                    (product_id, start_time, limit)
                )
            else:
                rows = self.session.execute(
                    self.get_candles_stmt,
                    (product_id, start_time, end_time)
                )
            
            # Convert to DataFrame with the standard format
            data = []
            for row in rows:
                data.append({
                    'timestamp': row.start_time,  # Mapping from start_time
                    'Open': float(row.open),      # Capitalized to match training format
                    'High': float(row.high),
                    'Low': float(row.low),
                    'Close': float(row.close),
                    'Volume': float(row.volume)
                })
            
            if not data:
                logger.warning(f"No data found for {product_id} from {start_time} to {end_time}")
                return pd.DataFrame()
            
            df = pd.DataFrame(data)
            df['timestamp'] = pd.to_datetime(df['timestamp'])
            df = df.set_index('timestamp').sort_index()
            
            # Rename columns to match training data format
            df = df.rename(columns={
                'Open': 'open',
                'High': 'high', 
                'Low': 'low',
                'Close': 'close',
                'Volume': 'volume'
            })
            
            logger.info(f"Fetched {len(df)} records for {product_id}")
            return df
            
        except Exception as e:
            logger.error(f"Error fetching OHLCV data for {product_id}: {str(e)}")
            raise
    
    def get_latest_data_for_prediction(self, 
                                     product_id: str, 
                                     seq_len: int = 288,
                                     config: Dict = None,
                                     existing_scalers: Dict = None) -> pd.DataFrame:
        """
        Fetch the latest data for prediction by reusing CryptoDataset logic.
        
        Args:
            product_id: Product ID
            seq_len: Sequence length required by the model
            config: Config dictionary matching training
            existing_scalers: Previously fitted scalers
        
        Returns:
            Processed DataFrame with enough features (uses CryptoDataset._enhance_crypto_features)
        """
        try:
            # Compute required time window with a buffer to keep enough data after cleaning
            buffer_multiplier = 2.0  # Increase buffer because cleaning may drop data
            lookback_minutes = seq_len * 5 * buffer_multiplier  # 5 minutes per candle
            start_time = datetime.utcnow() - timedelta(minutes=lookback_minutes)
            
            # Fetch raw data from Cassandra
            df_raw = self.fetch_ohlcv_data(product_id, start_time)
            
            if df_raw.empty:
                raise ValueError(f"No data available for {product_id}")
            
            # Create a temporary CSV for CryptoDataset
            import tempfile
            import os
            
            with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
                # Reset index to create a timestamp column
                df_temp = df_raw.reset_index()
                df_temp.to_csv(f.name, index=False)
                temp_csv_path = f.name
            
            try:
                # Use a sample config if none is provided
                if config is None:
                    config = {
                        'model': {
                            'seq_len': seq_len,
                            'pred_len': 12,
                            'enc_in': 26  # Will be adjusted after feature creation
                        },
                        'data': {
                            'freq': '5T',
                            'train_ratio': 0.8
                        }
                    }
                
                # Create a CryptoDataset instance to process data
                # NOTE: This reuses code from CryptoDataset
                crypto_dataset = CryptoDataset(
                    data_path=temp_csv_path,
                    config=config,
                    train=False,  # Not training mode
                    scalers=existing_scalers,  # Use existing scalers
                    test_mode=True  # Test mode, so augmentation is not applied
                )
                
                # Get processed data
                processed_data = crypto_dataset.data  # Processed DataFrame
                
                # Ensure enough data is available
                if len(processed_data) < seq_len:
                    raise ValueError(f"Insufficient data after processing: got {len(processed_data)}, need {seq_len}")
                
                # Take the latest seq_len records
                df_final = processed_data.tail(seq_len).copy()
                
                logger.info(f"Prepared {len(df_final)} records with {df_final.shape[1]} features for prediction for {product_id}")
                return df_final
                
            finally:
                # Cleanup temp file
                if os.path.exists(temp_csv_path):
                    os.unlink(temp_csv_path)
                    
        except Exception as e:
            logger.error(f"Error preparing prediction data for {product_id}: {str(e)}")
            raise
    
    def get_available_products(self) -> List[str]:
        """Get the list of available products in the database."""
        try:
            query = "SELECT DISTINCT product_id FROM candles"
            rows = self.session.execute(query)
            products = [row.product_id for row in rows]
            logger.info(f"Found {len(products)} products: {products}")
            return products
        except Exception as e:
            logger.error(f"Error getting available products: {str(e)}")
            return []
    
    def get_data_availability(self, product_id: str) -> Dict[str, any]:
        """Check data availability for a product."""
        try:
            query = """
                SELECT MIN(start_time) as earliest, MAX(start_time) as latest, COUNT(*) as count
                FROM candles WHERE product_id = ?
            """
            row = self.session.execute(query, (product_id,)).one()
            
            return {
                'product_id': product_id,
                'earliest': row.earliest,
                'latest': row.latest,
                'count': row.count
            }
        except Exception as e:
            logger.error(f"Error checking data availability for {product_id}: {str(e)}")
            return {}
    
    def create_scalers_from_historical_data(self, product_id: str, days_back: int = 30):
        """
        Create scalers from historical data for prediction.
        Reuse logic from CryptoDataset.
        """
        try:
            start_time = datetime.utcnow() - timedelta(days=days_back)
            df_historical = self.fetch_ohlcv_data(product_id, start_time)
            
            if len(df_historical) < 100:  # Reduced from 1000 to 100
                logger.warning(f"Insufficient historical data for {product_id}: {len(df_historical)} samples")
                return None
            
            # Create a temporary dataset to fit scalers
            import tempfile
            import os
            
            with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
                df_temp = df_historical.reset_index()
                df_temp.to_csv(f.name, index=False)
                temp_csv_path = f.name
            
            try:
                config = {
                    'model': {'seq_len': 288, 'pred_len': 12},
                    'data': {'freq': '5T', 'train_ratio': 0.8}
                }
                
                # Create dataset to fit scalers
                crypto_dataset = CryptoDataset(
                    data_path=temp_csv_path,
                    config=config,
                    train=True,  # Train mode to fit scalers
                    scalers=None,
                    test_mode=False
                )
                
                return crypto_dataset.scalers
                
            finally:
                if os.path.exists(temp_csv_path):
                    os.unlink(temp_csv_path)
                    
        except Exception as e:
            logger.error(f"Error creating scalers from historical data: {str(e)}")
            return None
