# Simple LSTM Training with Paimon Integration
# Focus: Simplicity, stability, production-ready

import yaml
import torch
import logging
from pathlib import Path
import sys
sys.path.append(str(Path(__file__).parent))

from lstm_attention_model import LSTMAttentionModel
from paimon_data_loader import PaimonDataLoader
from utils import TrainingTracker, EarlyStopper
from metrics import calculate_metrics

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class SimpleLSTMTrainer:
    """
    Simple and effective LSTM trainer
    
    Philosophy:
    - Simple is better than complex
    - Stability over bleeding-edge features
    - Production-ready over research experiments
    """
    
    def __init__(self, config_path: str = "configs/lstm_paimon_config.yaml"):
        with open(config_path) as f:
            self.config = yaml.safe_load(f)
        
        self.device = torch.device(self.config['training']['device'] 
                                  if torch.cuda.is_available() else 'cpu')
        logger.info(f"Using device: {self.device}")
        
        # Initialize data loader
        if self.config['data']['use_paimon']:
            logger.info("Loading data from Paimon lakehouse")
            self.data_loader = PaimonDataLoader(
                warehouse_path=self.config['data']['paimon_warehouse'],
                table_name=self.config['data']['paimon_table']
            )
        else:
            logger.info("Loading data from CSV file")
            from data_loader import CSVDataLoader
            self.data_loader = CSVDataLoader(self.config['data']['path'])
        
        # Initialize LSTM model
        self.model = LSTMAttentionModel(
            enc_in=self.config['model']['enc_in'],
            d_model=self.config['model']['d_model'],
            n_layers=self.config['model']['n_layers'],
            n_heads=self.config['model']['n_heads'],
            dropout=self.config['model']['dropout'],
            seq_len=self.config['model']['seq_len'],
            pred_len=self.config['model']['pred_len']
        ).to(self.device)
        
        logger.info("Initialized LSTM model")
        logger.info(f"Model parameters: {sum(p.numel() for p in self.model.parameters()):,}")
        
        # Simple optimizer
        self.optimizer = torch.optim.Adam(
            self.model.parameters(),
            lr=self.config['training']['lr'],
            weight_decay=self.config['training']['weight_decay']
        )
        
        # Simple scheduler
        self.scheduler = torch.optim.lr_scheduler.StepLR(
            self.optimizer,
            step_size=self.config['training']['lr_decay_step'],
            gamma=self.config['training']['lr_decay_factor']
        )
        
        # Simple loss function
        self.criterion = torch.nn.MSELoss()
        
        # Training trackers
        self.tracker = TrainingTracker()
        self.early_stopper = EarlyStopper(
            patience=self.config['training']['patience'],
            min_delta=self.config['training']['min_delta']
        )
    
    def train_epoch(self, train_loader):
        """Train for one epoch"""
        self.model.train()
        total_loss = 0
        
        for batch_idx, (inputs, targets) in enumerate(train_loader):
            inputs = inputs.to(self.device)
            targets = targets.to(self.device)
            
            # Forward pass
            self.optimizer.zero_grad()
            outputs = self.model(inputs)
            loss = self.criterion(outputs, targets)
            
            # Backward pass
            loss.backward()
            
            # Gradient clipping (prevent exploding gradients)
            if self.config['training']['grad_clip'] > 0:
                torch.nn.utils.clip_grad_norm_(
                    self.model.parameters(),
                    self.config['training']['grad_clip']
                )
            
            self.optimizer.step()
            total_loss += loss.item()
            
            # Log progress
            if batch_idx % self.config['training']['log_interval'] == 0:
                logger.info(f"Batch {batch_idx}/{len(train_loader)}, Loss: {loss.item():.6f}")
        
        return total_loss / len(train_loader)
    
    def validate(self, val_loader):
        """Validate model"""
        self.model.eval()
        total_loss = 0
        all_predictions = []
        all_targets = []
        
        with torch.no_grad():
            for inputs, targets in val_loader:
                inputs = inputs.to(self.device)
                targets = targets.to(self.device)
                
                outputs = self.model(inputs)
                loss = self.criterion(outputs, targets)
                
                total_loss += loss.item()
                all_predictions.append(outputs.cpu().numpy())
                all_targets.append(targets.cpu().numpy())
        
        avg_loss = total_loss / len(val_loader)
        metrics = calculate_metrics(all_predictions, all_targets)
        
        return avg_loss, metrics
    
    def train(self):
        """Main training loop"""
        logger.info("=" * 60)
        logger.info("Starting Simple LSTM Training with Paimon")
        logger.info("=" * 60)
        
        # Load data
        train_loader, val_loader, test_loader = self.data_loader.get_loaders(
            batch_size=self.config['training']['batch_size'],
            num_workers=self.config['training']['num_workers']
        )
        
        best_val_loss = float('inf')
        
        for epoch in range(self.config['training']['epochs']):
            logger.info(f"\nEpoch {epoch + 1}/{self.config['training']['epochs']}")
            logger.info("-" * 60)
            
            # Train
            train_loss = self.train_epoch(train_loader)
            
            # Validate
            val_loss, val_metrics = self.validate(val_loader)
            
            # Update learning rate
            self.scheduler.step()
            
            # Log results
            logger.info(f"Train Loss: {train_loss:.6f}")
            logger.info(f"Val Loss: {val_loss:.6f}")
            logger.info(f"Val MAE: {val_metrics.get('mae', 0):.6f}")
            logger.info(f"Val RMSE: {val_metrics.get('rmse', 0):.6f}")
            logger.info(f"Learning Rate: {self.scheduler.get_last_lr()[0]:.6f}")
            
            # Track progress
            self.tracker.update(epoch, train_loss, val_loss, val_metrics)
            
            # Save best model
            if val_loss < best_val_loss:
                best_val_loss = val_loss
                checkpoint_path = Path(self.config['training']['checkpoint_dir']) / f"lstm_best_epoch_{epoch}.pt"
                checkpoint_path.parent.mkdir(exist_ok=True)
                torch.save({
                    'epoch': epoch,
                    'model_state_dict': self.model.state_dict(),
                    'optimizer_state_dict': self.optimizer.state_dict(),
                    'val_loss': val_loss,
                    'val_metrics': val_metrics,
                    'config': self.config
                }, checkpoint_path)
                logger.info(f"✓ Saved best model to {checkpoint_path}")
            
            # Early stopping
            if self.early_stopper.should_stop(val_loss):
                logger.info(f"Early stopping triggered at epoch {epoch + 1}")
                break
        
        logger.info("\n" + "=" * 60)
        logger.info("Training completed!")
        logger.info("=" * 60)
        
        # Final evaluation on test set
        test_loss, test_metrics = self.validate(test_loader)
        logger.info("\nFinal Test Results:")
        logger.info(f"Test Loss: {test_loss:.6f}")
        logger.info(f"Test MAE: {test_metrics.get('mae', 0):.6f}")
        logger.info(f"Test RMSE: {test_metrics.get('rmse', 0):.6f}")
        logger.info(f"Direction Accuracy: {test_metrics.get('direction_accuracy', 0):.2%}")
        
        return test_metrics


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Train Simple LSTM Model')
    parser.add_argument('--config', type=str, default='configs/lstm_paimon_config.yaml',
                       help='Path to config file')
    args = parser.parse_args()
    
    trainer = SimpleLSTMTrainer(args.config)
    metrics = trainer.train()
    
    print(f"\n{'='*60}")
    print("Final test metrics:")
    for key, value in metrics.items():
        print(f"  {key}: {value:.6f}")
    print(f"{'='*60}")
