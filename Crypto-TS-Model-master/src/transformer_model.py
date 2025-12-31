# Transformer-based Time Series Model for Cryptocurrency Prediction
# Modern architecture using pure attention mechanism

import torch
import torch.nn as nn
import torch.nn.functional as F
from typing import Dict, Any
import math


class PositionalEncoding(nn.Module):
    """Sinusoidal positional encoding for time series"""
    def __init__(self, d_model: int, max_len: int = 5000, dropout: float = 0.1):
        super().__init__()
        self.dropout = nn.Dropout(p=dropout)
        
        position = torch.arange(max_len).unsqueeze(1)
        div_term = torch.exp(torch.arange(0, d_model, 2) * (-math.log(10000.0) / d_model))
        pe = torch.zeros(max_len, 1, d_model)
        pe[:, 0, 0::2] = torch.sin(position * div_term)
        pe[:, 0, 1::2] = torch.cos(position * div_term)
        self.register_buffer('pe', pe)
    
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = x + self.pe[:x.size(0)]
        return self.dropout(x)


class TimeSeriesEmbedding(nn.Module):
    """Enhanced embedding for time series data"""
    def __init__(self, input_dim: int, d_model: int, dropout: float = 0.1):
        super().__init__()
        self.value_embedding = nn.Linear(input_dim, d_model)
        self.temporal_embedding = nn.Linear(1, d_model)
        self.dropout = nn.Dropout(dropout)
        
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x shape: [batch, seq_len, features]
        batch_size, seq_len, _ = x.shape
        
        # Value embedding
        value_emb = self.value_embedding(x)
        
        # Temporal embedding (position in sequence)
        temporal_pos = torch.arange(seq_len, device=x.device).float().unsqueeze(0).unsqueeze(-1)
        temporal_pos = temporal_pos.expand(batch_size, -1, -1) / seq_len
        temporal_emb = self.temporal_embedding(temporal_pos)
        
        return self.dropout(value_emb + temporal_emb)


class TransformerTimeSeriesModel(nn.Module):
    """
    Modern Transformer-based model for cryptocurrency price prediction.
    
    Advantages over LSTM:
    - Parallel processing (much faster training)
    - Better at capturing long-range dependencies
    - More interpretable through attention weights
    - State-of-the-art performance on time series tasks
    """
    
    def __init__(self, config: Dict[str, Any]):
        super().__init__()
        model_cfg = config['model']
        
        # Model dimensions
        self.input_dim = model_cfg['enc_in']
        self.d_model = model_cfg['d_model']
        self.n_heads = model_cfg.get('n_heads', 8)
        self.n_layers = model_cfg.get('n_layers', 4)
        self.d_ff = model_cfg.get('d_ff', self.d_model * 4)
        self.dropout = model_cfg.get('dropout', 0.1)
        self.pred_len = model_cfg['pred_len']
        self.output_dim = model_cfg.get('output_dim', 1)
        
        # Input embedding
        self.embedding = TimeSeriesEmbedding(
            self.input_dim, 
            self.d_model, 
            self.dropout
        )
        
        # Positional encoding
        self.pos_encoder = PositionalEncoding(
            self.d_model, 
            max_len=5000, 
            dropout=self.dropout
        )
        
        # Transformer encoder
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=self.d_model,
            nhead=self.n_heads,
            dim_feedforward=self.d_ff,
            dropout=self.dropout,
            activation='gelu',
            batch_first=True,
            norm_first=True  # Pre-LN architecture (more stable)
        )
        
        self.transformer_encoder = nn.TransformerEncoder(
            encoder_layer,
            num_layers=self.n_layers,
            norm=nn.LayerNorm(self.d_model)
        )
        
        # Projection head for prediction
        self.projection = nn.Sequential(
            nn.Linear(self.d_model, self.d_model // 2),
            nn.GELU(),
            nn.Dropout(self.dropout),
            nn.Linear(self.d_model // 2, self.pred_len * self.output_dim)
        )
        
        # Initialize weights
        self._init_weights()
    
    def _init_weights(self):
        """Initialize weights using Xavier initialization"""
        for p in self.parameters():
            if p.dim() > 1:
                nn.init.xavier_uniform_(p)
    
    def forward(self, x: torch.Tensor, mask: torch.Tensor = None) -> torch.Tensor:
        """
        Forward pass
        
        Args:
            x: Input tensor [batch, seq_len, features]
            mask: Optional attention mask
            
        Returns:
            predictions: [batch, pred_len, output_dim]
        """
        batch_size = x.shape[0]
        
        # Embedding
        x = self.embedding(x)  # [batch, seq_len, d_model]
        
        # Add positional encoding
        x = x.transpose(0, 1)  # [seq_len, batch, d_model]
        x = self.pos_encoder(x)
        x = x.transpose(0, 1)  # [batch, seq_len, d_model]
        
        # Transformer encoding
        encoded = self.transformer_encoder(x, src_key_padding_mask=mask)
        
        # Use the last hidden state for prediction
        last_hidden = encoded[:, -1, :]  # [batch, d_model]
        
        # Project to prediction
        output = self.projection(last_hidden)  # [batch, pred_len * output_dim]
        output = output.view(batch_size, self.pred_len, self.output_dim)
        
        return output
    
    def get_attention_weights(self, x: torch.Tensor) -> list:
        """Extract attention weights for interpretability"""
        attention_weights = []
        
        def hook_fn(module, input, output):
            # Extract attention weights from each layer
            attention_weights.append(output[1] if len(output) > 1 else None)
        
        # Register hooks
        hooks = []
        for layer in self.transformer_encoder.layers:
            hooks.append(layer.self_attn.register_forward_hook(hook_fn))
        
        # Forward pass
        with torch.no_grad():
            self.forward(x)
        
        # Remove hooks
        for hook in hooks:
            hook.remove()
        
        return attention_weights


class MultiHorizonTransformer(nn.Module):
    """
    Advanced model with multi-horizon prediction capabilities.
    Predicts multiple future time steps with different prediction heads.
    """
    
    def __init__(self, config: Dict[str, Any]):
        super().__init__()
        model_cfg = config['model']
        
        self.input_dim = model_cfg['enc_in']
        self.d_model = model_cfg['d_model']
        self.horizons = model_cfg.get('prediction_horizons', [1, 3, 6, 12])  # 1h, 3h, 6h, 12h
        self.output_dim = model_cfg.get('output_dim', 1)
        
        # Shared encoder (same as above)
        self.embedding = TimeSeriesEmbedding(self.input_dim, self.d_model)
        self.pos_encoder = PositionalEncoding(self.d_model)
        
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=self.d_model,
            nhead=model_cfg.get('n_heads', 8),
            dim_feedforward=model_cfg.get('d_ff', self.d_model * 4),
            dropout=model_cfg.get('dropout', 0.1),
            activation='gelu',
            batch_first=True,
            norm_first=True
        )
        
        self.transformer_encoder = nn.TransformerEncoder(
            encoder_layer,
            num_layers=model_cfg.get('n_layers', 4)
        )
        
        # Separate prediction heads for each horizon
        self.prediction_heads = nn.ModuleDict({
            f'horizon_{h}': nn.Sequential(
                nn.Linear(self.d_model, self.d_model // 2),
                nn.GELU(),
                nn.Dropout(0.1),
                nn.Linear(self.d_model // 2, h * self.output_dim)
            ) for h in self.horizons
        })
        
        self._init_weights()
    
    def _init_weights(self):
        for p in self.parameters():
            if p.dim() > 1:
                nn.init.xavier_uniform_(p)
    
    def forward(self, x: torch.Tensor, horizon: int = None) -> Dict[int, torch.Tensor]:
        """
        Forward pass with multi-horizon predictions
        
        Args:
            x: Input tensor [batch, seq_len, features]
            horizon: If specified, return only this horizon
            
        Returns:
            Dictionary of predictions for each horizon
        """
        # Embedding and encoding (same as above)
        x = self.embedding(x)
        x = x.transpose(0, 1)
        x = self.pos_encoder(x)
        x = x.transpose(0, 1)
        
        encoded = self.transformer_encoder(x)
        last_hidden = encoded[:, -1, :]
        
        # Predict for each horizon
        predictions = {}
        horizons_to_predict = [horizon] if horizon else self.horizons
        
        for h in horizons_to_predict:
            head = self.prediction_heads[f'horizon_{h}']
            pred = head(last_hidden)
            pred = pred.view(-1, h, self.output_dim)
            predictions[h] = pred
        
        return predictions


def get_model(config: Dict[str, Any], model_type: str = 'transformer') -> nn.Module:
    """
    Factory function to get the appropriate model
    
    Args:
        config: Configuration dictionary
        model_type: 'transformer' or 'multi_horizon'
    
    Returns:
        Initialized model
    """
    if model_type == 'transformer':
        return TransformerTimeSeriesModel(config)
    elif model_type == 'multi_horizon':
        return MultiHorizonTransformer(config)
    else:
        raise ValueError(f"Unknown model type: {model_type}")


if __name__ == "__main__":
    # Test the model
    import yaml
    
    config = {
        'model': {
            'enc_in': 6,  # OHLCV + Volume
            'd_model': 256,
            'n_heads': 8,
            'n_layers': 4,
            'd_ff': 1024,
            'dropout': 0.1,
            'pred_len': 12,
            'output_dim': 1,
            'prediction_horizons': [1, 3, 6, 12]
        }
    }
    
    # Test single-horizon model
    model = TransformerTimeSeriesModel(config)
    x = torch.randn(32, 24, 6)  # batch=32, seq_len=24, features=6
    output = model(x)
    print(f"Single-horizon output shape: {output.shape}")  # [32, 12, 1]
    
    # Test multi-horizon model
    multi_model = MultiHorizonTransformer(config)
    outputs = multi_model(x)
    for horizon, pred in outputs.items():
        print(f"Horizon {horizon}h output shape: {pred.shape}")
