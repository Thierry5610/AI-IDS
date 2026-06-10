"""Model architectures for the neural models.

These MUST match the definitions used during training exactly, byte for byte in
structure, or load_state_dict will fail or load garbage. Copied from the Kaggle
pipeline reference. Do not "improve" them here.
"""
import torch.nn as nn


class CNNLSTM(nn.Module):
    def __init__(self, input_size=1, seq_len=56, num_classes=15):
        super().__init__()
        self.cnn = nn.Sequential(
            nn.Conv1d(in_channels=input_size, out_channels=64, kernel_size=3, padding=1),
            nn.BatchNorm1d(64), nn.ReLU(),
            nn.Conv1d(in_channels=64, out_channels=128, kernel_size=3, padding=1),
            nn.BatchNorm1d(128), nn.ReLU(), nn.Dropout(0.2),
        )
        self.lstm = nn.LSTM(
            input_size=128, hidden_size=128, num_layers=2,
            batch_first=True, dropout=0.2, bidirectional=True,
        )
        self.classifier = nn.Sequential(
            nn.Linear(256, 128), nn.ReLU(), nn.Dropout(0.3), nn.Linear(128, num_classes),
        )

    def forward(self, x):
        # x: (batch, seq_len, 1) -> (batch, 1, seq_len) for Conv1d
        x = x.permute(0, 2, 1)
        x = self.cnn(x)
        x = x.permute(0, 2, 1)
        x, _ = self.lstm(x)
        x = x[:, -1, :]
        return self.classifier(x)


class Autoencoder(nn.Module):
    def __init__(self, input_dim=56):
        super().__init__()
        self.encoder = nn.Sequential(
            nn.Linear(input_dim, 128), nn.BatchNorm1d(128), nn.ReLU(), nn.Dropout(0.2),
            nn.Linear(128, 64), nn.BatchNorm1d(64), nn.ReLU(),
            nn.Linear(64, 32), nn.ReLU(),
        )
        self.decoder = nn.Sequential(
            nn.Linear(32, 64), nn.BatchNorm1d(64), nn.ReLU(),
            nn.Linear(64, 128), nn.BatchNorm1d(128), nn.ReLU(), nn.Dropout(0.2),
            nn.Linear(128, input_dim),
        )

    def forward(self, x):
        return self.decoder(self.encoder(x))