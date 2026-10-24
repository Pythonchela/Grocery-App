import StoreProfileClient from '../../../components/admin/StoreProfileClient';

export const metadata = {
  title: 'My shop',
  description: 'The store profile: hours, delivery area and pickup address.',
};

export default function AdminStorePage() {
  return <StoreProfileClient />;
}
