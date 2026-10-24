import BulkImportClient from '../../../components/admin/BulkImportClient';

export default function AdminImportPage() {
  return (
    <div className="min-h-screen bg-surface-sunken">
      <div className="max-w-4xl mx-auto px-4 py-8">
        <BulkImportClient />
      </div>
    </div>
  );
}
