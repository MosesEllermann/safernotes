from __future__ import annotations

from rest_framework import response, views


class SearchStatusView(views.APIView):
    def get(self, request):
        return response.Response(
            {
                "server_content_search": False,
                "local_decrypted_index_required": True,
                "message": "Search queries and plaintext search tokens are never accepted by the API.",
            }
        )

