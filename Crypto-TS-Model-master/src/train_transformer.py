# Transformer Training Integration with Paimon

import yaml
import torch
import logging
from pathlib import Path
import sys
sys.path.append(str(Path(__file__).parent))

from transformer_model import TransformerTimeSeriesModel, MultiHorizonTransformer
from paimon_data_loader import PaimonDataLoader
from utils import TrainingTracker, EarlyStopper
from metrics import calculate_metrics

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class TransformerTrainer:
    """
    Training pipeline for Transformer-based cryptocurrency price prediction
    
    Improvements over LSTM:
    - Parallel processing (faster training)
    - Better long-range dependencies
    - More interpretable attention weights
    - Multi-horizon predictions
    """
    
    def __init__(self, config_path: str = "configs/transformer_config.yaml"):
        with open(config_path) as f:
            self.config = yaml.safe_load(f)
        
        self.device = torch.device(self.config['training']['device'] 
                                  if torch.cuda.is_available() else 'cpu')
        logger.info(f"Using device: {self.device}")
        
        # Initialize data loader
        if self.config['data']['use_paimon']:
            self.data_loader = PaimonDataLoader(
                warehouse_path=self.config['data']['paimon_warehouse'],
                table_name=self.config['data']['paimon_table']
            )
        else:
            from data_loader import CSVDataLoader
            self.data_loader = CSVDataLoader(self.config['data']['path'])
        
        # Initialize model
        if self.config['training'].get('use_multi_task', False):
            self.model = MultiHorizonTransformer(
                enc_in=self.config['model']['enc_in'],
                d_model=self.config['model']['d_model'],
                n_heads=self.config['model']['n_heads'],
                n_layers=self.config['model']['n_layers'],
                d_ff=self.config['model']['d_ff'],
                dropout=self.config['model']['dropout'],
                seq_len=self.config['model']['seq_len'],
                prediction_horizons=self.config['model']['prediction_horizons']
            ).to(self.device)
        else:
            self.model = TransformerTimeSeriesModel(
                enc_in=self.config['model']['enc_in'],
                d_model=self.config['model']['d_model'],
                n_heads=self.config['model']['n_heads'],
                n_layers=self.config['model']['n_layers'],
                d_ff=self.config['model']['d_ff'],
                dropout=self.config['model']['dropout'],
                seq_len=self.config['model']['seq_len'],
                pred_len=self.config['model']['pred_len']
            ).to(self.device)
        
        logger.info(f"Initialized {self.model.__class__.__name__} model")
        logger.info(f"Model parameters: {sum(p.numel() for p in self.model.parameters()):,}")
        
        # Initialize optimizer
        self.optimizer = self._get_optimizer()
        self.scheduler = self._get_scheduler()
        
        # Loss function
        self.criterion = self._get_loss_fn()
        
        # Training trackers
        self.tracker = TrainingTracker()
        self.early_stopper = EarlyStopper(
            patience=self.config['training']['patience'],
            min_delta=self.config['training']['min_delta']
        )
        
        # Mixed precision training
        self.use_amp = self.config['training'].get('use_amp', False)
        if self.use_amp:
            self.scaler = torch.cuda.amp.GradScaler()
    
    def _get_optimizer(self):
        """Initialize optimizer"""
        if self.config['training']['optimizer'] == 'adamw':
            return torch.optim.AdamW(
                self.model.parameters(),
                lr=self.config['training']['lr'],
                betas=self.config['training']['betas'],
                eps=self.config['training']['eps'],
                weight_decay=self.config['training']['weight_decay']
            )
        elif self.config['training']['optimizer'] == 'adam':
            return torch.optim.Adam(
                self.model.parameters(),
                lr=self.config['training']['lr'],
                weight_decay=self.config['training'].get('weight_decay', 0.0)
            )
        else:
            raise ValueError(f"Unknown optimizer: {self.config['training']['optimizer']}")
    
    def _get_scheduler(self):
        """Initialize learning rate scheduler"""
        if self.config['training']['lr_scheduler'] == 'onecycle':
            return torch.optim.lr_scheduler.OneCycleLR(
                self.optimizer,
                max_lr=self.config['training']['max_lr'],
                epochs=self.config['training']['epochs'],
                steps_per_epoch=100,  # Will be updated during training
                pct_start=self.config['training']['pct_start']
            )
        elif self.config['training']['lr_scheduler'] == 'cosine':
            return torch.optim.lr_scheduler.CosineAnnealingLR(
                self.optimizer,
                T_max=self.config['training']['epochs']
            )
        else:
            return None
    
    def _get_loss_fn(self):
        """Initialize loss function"""
        loss_fn = self.config['training']['loss_fn']
        if loss_fn == 'huber':
            return torch.nn.HuberLoss(delta=self.config['training']['huber_delta'])
        elif loss_fn == 'mse':
            return torch.nn.MSELoss()
        elif loss_fn == 'mae':
            return torch.nn.L1Loss()
        else:
            raise ValueError(f"Unknown loss function: {loss_fn}")
    
    def train_epoch(self, train_loader):
        """Train for one epoch"""
        self.model.train()
        total_loss = 0
        
        for batch_idx, (inputs, targets) in enumerate(train_loader):
            inputs = inputs.to(self.device)
            targets = targets.to(self.device)
            
            self.optimizer.zero_grad()
            
            if self.use_amp:
                with torch.cuda.amp.autocast():
                    outputs = self.model(inputs)
                    loss = self.criterion(outputs, targets)
                
                self.scaler.scale(loss).backward()
                
                # Gradient clipping
                if self.config['training']['grad_clip'] > 0:
                    self.scaler.unscale_(self.optimizer)
                    torch.nn.utils.clip_grad_norm_(
                        self.model.parameters(),
                        self.config['training']['grad_clip']
                    )
                
                self.scaler.step(self.optimizer)
                self.scaler.update()
            else:
                outputs = self.model(inputs)
                loss = self.criterion(outputs, targets)
                loss.backward()
                
                if self.config['training']['grad_clip'] > 0:
                    torch.nn.utils.clip_grad_norm_(
                        self.model.parameters(),
                        self.config['training']['grad_clip']
                    )
                
                self.optimizer.step()
            
            if self.scheduler:
                self.scheduler.step()
            
            total_loss += loss.item()
            
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
        logger.info("Starting training...")
        
        # Load data
        train_loader, val_loader, test_loader = self.data_loader.get_loaders(
            batch_size=self.config['training']['batch_size'],
            num_workers=self.config['training']['num_workers']
        )
        
        best_val_loss = float('inf')
        
        for epoch in range(self.config['training']['epochs']):
            logger.info(f"\nEpoch {epoch + 1}/{self.config['training']['epochs']}")
            
            # Train
            train_loss = self.train_epoch(train_loader)
            
            # Validate
            val_loss, val_metrics = self.validate(val_loader)
            
            logger.info(f"Train Loss: {train_loss:.6f}")
            logger.info(f"Val Loss: {val_loss:.6f}")
            logger.info(f"Val Metrics: {val_metrics}")
            
            # Track progress
            self.tracker.update(epoch, train_loss, val_loss, val_metrics)
            
            # Save checkpoint
            if val_loss < best_val_loss:
                best_val_loss = val_loss
                checkpoint_path = Path(self.config['training']['checkpoint_dir']) / f"best_epoch_{epoch}.pt"
                checkpoint_path.parent.mkdir(exist_ok=True)
                torch.save({
                    'epoch': epoch,
                    'model_state_dict': self.model.state_dict(),
                    'optimizer_state_dict': self.optimizer.state_dict(),
                    'val_loss': val_loss,
                    'val_metrics': val_metrics,
                    'config': self.config
                }, checkpoint_path)
                logger.info(f"Saved best model to {checkpoint_path}")
            
            # Early stopping
            if self.early_stopper.should_stop(val_loss):
                logger.info(f"Early stopping triggered at epoch {epoch + 1}")
                break
        
        logger.info("Training completed!")
        
        # Final evaluation on test set
        test_loss, test_metrics = self.validate(test_loader)
        logger.info(f"\nTest Loss: {test_loss:.6f}")
        logger.info(f"Test Metrics: {test_metrics}")
        
        return test_metrics


if __name__ == "__main__":
    trainer = TransformerTrainer("configs/transformer_config.yaml")
    metrics = trainer.train()
    print(f"\nFinal test metrics: {metrics}")
