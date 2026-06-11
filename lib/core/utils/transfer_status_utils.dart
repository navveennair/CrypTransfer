bool isFailedTransferStatus(String? status) =>
    status == 'aborted' || status == 'connection_lost' || status == 'failed';
